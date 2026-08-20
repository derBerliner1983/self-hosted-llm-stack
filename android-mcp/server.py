"""MCP-Dienst für Android-Builds.

Stellt dem Sprachmodell Werkzeuge bereit, um Android-Projekte anzulegen, zu
bauen und zu testen:

  - list_projects()                  Projekte im Arbeitsbereich auflisten
  - create_project(name, package)    Neues Gradle-Projekt anlegen
  - gradle(project, args)            Gradle-Aufgabe ausführen (assembleDebug, test, …)
  - sdk_packages()                   Installierte SDK-Pakete anzeigen
  - install_sdk_package(package)     Weiteres SDK-Paket nachinstallieren

Anders als sandbox-mcp laufen die Befehle DIREKT in diesem Container, nicht
in einem Wegwerf-Container pro Aufruf — Android-Builds brauchen Netzwerk,
einen persistenten Gradle-Cache und Minuten statt Sekunden. Der Quelltext
der Projekte liegt unter ANDROID_WORKSPACE (Standard /workspace); dasselbe
Volume ist auch im mcp-Container eingehängt, sodass die
Dateisystem-Werkzeuge die Dateien bearbeiten können.

This file is part of Self-Hosted AI Stack. MIT License.
"""

import os
import re
import shutil
import subprocess

from mcp.server.mcpserver import MCPServer

WORKSPACE = os.environ.get("ANDROID_WORKSPACE", "/workspace")
DEFAULT_TIMEOUT = int(os.environ.get("ANDROID_DEFAULT_TIMEOUT", "600"))
MAX_TIMEOUT = int(os.environ.get("ANDROID_MAX_TIMEOUT", "1800"))
ANDROID_HOME = os.environ.get("ANDROID_HOME", "/opt/android-sdk")
# Gradle-Version für den Wrapper neu angelegter Projekte. Muss zum
# Android-Gradle-Plugin unten passen, sonst bricht der erste Build ab.
GRADLE_VERSION = os.environ.get("ANDROID_GRADLE_VERSION", "8.7")
AGP_VERSION = os.environ.get("ANDROID_AGP_VERSION", "8.5.2")
COMPILE_SDK = int(os.environ.get("ANDROID_COMPILE_SDK", "34"))
MIN_SDK = int(os.environ.get("ANDROID_MIN_SDK", "24"))

MAX_OUTPUT_CHARS = 20_000

HOST = os.environ.get("FASTMCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("FASTMCP_PORT", "8000"))

mcp = MCPServer("Android-Build")

# Projektnamen landen unverändert in Pfaden — deshalb streng validieren,
# damit "../" oder absolute Pfade nicht aus dem Arbeitsbereich ausbrechen.
_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,63}$")
_PACKAGE_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$")


def _clip(text):
    if len(text) > MAX_OUTPUT_CHARS:
        return text[:MAX_OUTPUT_CHARS] + f"\n… [Ausgabe nach {MAX_OUTPUT_CHARS} Zeichen gekürzt]"
    return text


def _project_dir(name):
    """Projektverzeichnis auflösen und sicherstellen, dass es im
    Arbeitsbereich liegt (kein Ausbruch über '..' o. Ä.)."""
    if not _NAME_RE.match(name or ""):
        raise ValueError(
            "Ungültiger Projektname. Erlaubt: Buchstabe am Anfang, danach "
            "Buchstaben/Ziffern/Unterstrich/Bindestrich, max. 64 Zeichen."
        )
    path = os.path.realpath(os.path.join(WORKSPACE, name))
    if os.path.commonpath([path, os.path.realpath(WORKSPACE)]) != os.path.realpath(WORKSPACE):
        raise ValueError("Projektpfad liegt außerhalb des Arbeitsbereichs.")
    return path


def _run(cmd, cwd, timeout_seconds):
    timeout_seconds = max(1, min(int(timeout_seconds), MAX_TIMEOUT))
    env = dict(os.environ)
    env.setdefault("ANDROID_HOME", ANDROID_HOME)
    env.setdefault("ANDROID_SDK_ROOT", ANDROID_HOME)
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, env=env, timeout=timeout_seconds,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            errors="replace", check=False,
        )
        return {"output": _clip(proc.stdout), "exit_code": proc.returncode, "timed_out": False}
    except subprocess.TimeoutExpired as exc:
        partial = exc.output or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        return {
            "output": _clip(partial),
            "exit_code": None,
            "timed_out": True,
            "error": f"Zeitlimit von {timeout_seconds}s überschritten.",
        }
    except OSError as exc:
        return {"output": "", "exit_code": None, "timed_out": False, "error": str(exc)}


# ── Vorlage für neue Projekte ──────────────────────────────────────────────
# Bewusst minimal und ohne Kotlin/Compose gehalten: weniger bewegliche Teile,
# die zwischen Gradle-, AGP- und Kotlin-Versionen zueinander passen müssen.

_SETTINGS_GRADLE = """pluginManagement {{
    repositories {{
        google()
        mavenCentral()
        gradlePluginPortal()
    }}
}}
dependencyResolutionManagement {{
    repositories {{
        google()
        mavenCentral()
    }}
}}
rootProject.name = "{name}"
include(":app")
"""

_ROOT_BUILD_GRADLE = """plugins {{
    id("com.android.application") version "{agp}" apply false
}}
"""

_APP_BUILD_GRADLE = """plugins {{
    id("com.android.application")
}}

android {{
    namespace = "{package_name}"
    compileSdk = {compile_sdk}

    defaultConfig {{
        applicationId = "{package_name}"
        minSdk = {min_sdk}
        targetSdk = {compile_sdk}
        versionCode = 1
        versionName = "1.0"
    }}

    buildTypes {{
        release {{
            isMinifyEnabled = false
        }}
    }}

    compileOptions {{
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }}
}}

dependencies {{
    testImplementation("junit:junit:4.13.2")
}}
"""

_GRADLE_PROPERTIES = """org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=true
"""

_MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="{name}"
        android:theme="@android:style/Theme.Material.Light">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
"""

_MAIN_ACTIVITY = """package {package_name};

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {{
    @Override
    protected void onCreate(Bundle savedInstanceState) {{
        super.onCreate(savedInstanceState);
        TextView text = new TextView(this);
        text.setText("Hallo von {name}");
        setContentView(text);
    }}
}}
"""

_EXAMPLE_TEST = """package {package_name};

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public class ExampleUnitTest {{
    @Test
    public void addition_isCorrect() {{
        assertEquals(4, 2 + 2);
    }}
}}
"""


@mcp.tool()
def list_projects() -> dict:
    """START HIER FÜR ALLES RUND UM ANDROID. Listet die Android-Projekte im
    Arbeitsbereich auf.

    Dieser Dienst IST die Android-Umgebung: Android SDK, Gradle und JDK sind
    hier installiert und einsatzbereit. Suche Android NICHT mit run_shell in
    der Code-Sandbox - dort gibt es absichtlich kein SDK, und du wirst es
    dort auch nach beliebig vielen Versuchen nicht finden.

    Nutze dieses Werkzeug zuerst, um zu sehen, welche Projekte es gibt,
    bevor du baust oder Dateien änderst. Ist noch keines da, legst du mit
    create_project eines an.
    """
    try:
        entries = sorted(
            name for name in os.listdir(WORKSPACE)
            if os.path.isdir(os.path.join(WORKSPACE, name)) and not name.startswith(".")
        )
    except OSError as exc:
        return {"error": str(exc), "projects": []}

    projects = []
    for name in entries:
        path = os.path.join(WORKSPACE, name)
        projects.append({
            "name": name,
            "path": path,
            "has_gradle_wrapper": os.path.exists(os.path.join(path, "gradlew")),
        })
    return {"workspace": WORKSPACE, "projects": projects}


@mcp.tool()
def create_project(name: str, package_name: str = "com.example.app") -> dict:
    """Legt ein neues, baubares Android-Projekt (Java, Gradle) im
    Arbeitsbereich an — inklusive Gradle-Wrapper, Manifest, einer
    MainActivity und einem Beispiel-Unittest.

    Danach kannst du die Quelldateien mit den Dateisystem-Werkzeugen
    bearbeiten und mit dem Werkzeug 'gradle' bauen bzw. testen.

    Parameter heißen 'name' und 'package_name', beide einfache Strings.
    Meldet der Aufruf einen Schema-Fehler: einfach mit denselben zwei
    Strings erneut aufrufen, NICHT auf code_sandbox ausweichen - dort gibt
    es keinen Zugriff auf /workspace und keine Schreibrechte außerhalb von
    /work und /tmp, ein Projekt lässt sich dort unter keinen Umständen
    anlegen.

    :param name: Projektname (Buchstaben, Ziffern, _ und -), wird auch der Verzeichnisname.
    :param package_name: Java-Paketname, z. B. "com.example.meineapp".
    """
    try:
        root = _project_dir(name)
    except ValueError as exc:
        return {"error": str(exc)}

    if not _PACKAGE_RE.match(package_name or ""):
        return {"error": "Ungültiger Paketname. Erwartet z. B. 'com.example.meineapp'."}

    if os.path.exists(root):
        return {"error": f"Projekt '{name}' existiert bereits unter {root}."}

    pkg_path = os.path.join(root, "app", "src", "main", "java", *package_name.split("."))
    test_path = os.path.join(root, "app", "src", "test", "java", *package_name.split("."))
    os.makedirs(pkg_path)
    os.makedirs(test_path)

    files = {
        os.path.join(root, "settings.gradle.kts"): _SETTINGS_GRADLE.format(name=name),
        os.path.join(root, "build.gradle.kts"): _ROOT_BUILD_GRADLE.format(agp=AGP_VERSION),
        os.path.join(root, "gradle.properties"): _GRADLE_PROPERTIES,
        os.path.join(root, "app", "build.gradle.kts"): _APP_BUILD_GRADLE.format(
            package_name=package_name, compile_sdk=COMPILE_SDK, min_sdk=MIN_SDK,
        ),
        os.path.join(root, "app", "src", "main", "AndroidManifest.xml"): _MANIFEST.format(name=name),
        os.path.join(pkg_path, "MainActivity.java"): _MAIN_ACTIVITY.format(
            package_name=package_name, name=name,
        ),
        os.path.join(test_path, "ExampleUnitTest.java"): _EXAMPLE_TEST.format(
            package_name=package_name,
        ),
    }
    for path, content in files.items():
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(content)

    # Gradle-Wrapper erzeugen, damit das Projekt eigenständig baubar ist
    # (und die Gradle-Version im Projekt festgeschrieben ist).
    wrapper = _run(
        ["gradle", "wrapper", "--gradle-version", GRADLE_VERSION],
        cwd=root, timeout_seconds=DEFAULT_TIMEOUT,
    )
    # Am tatsächlich entstandenen gradlew prüfen, nicht am exit_code: _run()
    # liefert exit_code=None sowohl bei Zeitüberschreitung ALS AUCH bei einem
    # OSError (z. B. "gradle" gar nicht im PATH) - eine Prüfung auf
    # "exit_code not in (0, None)" übersieht den OSError-Fall komplett und
    # meldete bisher fälschlich Erfolg, obwohl gar kein Wrapper entstanden
    # ist (genau das hat zuvor lange Fehlersuche verursacht: Projektdateien
    # lagen, gradlew fehlte, und create_project() hat trotzdem nichts
    # gewarnt).
    if not os.path.exists(os.path.join(root, "gradlew")):
        return {
            "created": root,
            "warning": "Projektdateien liegen, aber der Gradle-Wrapper konnte nicht erzeugt werden.",
            "wrapper_output": wrapper.get("output", ""),
            "wrapper_error": wrapper.get("error", ""),
        }

    return {
        "created": root,
        "package_name": package_name,
        "next_steps": (
            f"Bauen mit gradle(project='{name}', args='assembleDebug'), "
            f"Tests mit gradle(project='{name}', args='test')."
        ),
    }


@mcp.tool()
def gradle(project: str, args: str = "assembleDebug", timeout_seconds: int = DEFAULT_TIMEOUT) -> dict:
    """Führt eine Gradle-Aufgabe in einem Projekt des Arbeitsbereichs aus und
    gibt die Ausgabe sowie den Exit-Code zurück.

    Gängige Aufgaben: 'assembleDebug' (Debug-APK bauen), 'test'
    (Unittests), 'tasks' (verfügbare Aufgaben anzeigen), 'clean'.
    Der erste Lauf dauert lange, weil Gradle und alle Abhängigkeiten
    heruntergeladen werden; danach greift der persistente Cache.

    Nach 'assembleDebug' liegt die APK unter
    <projekt>/app/build/outputs/apk/debug/app-debug.apk. Damit der Nutzer sie
    herunterladen kann, verschiebe sie mit dem Dateisystem-Werkzeug
    move_file nach /exchange (z. B. /exchange/<projekt>.apk) - das ist der
    Ordner, den er direkt im Browser sieht, nicht /workspace.

    :param project: Name des Projekts im Arbeitsbereich (siehe list_projects).
    :param args: Gradle-Argumente, z. B. "assembleDebug" oder "test --info".
    :param timeout_seconds: Zeitlimit in Sekunden (Standard 600, maximal 1800).
    """
    try:
        root = _project_dir(project)
    except ValueError as exc:
        return {"error": str(exc)}

    if not os.path.isdir(root):
        return {"error": f"Projekt '{project}' nicht gefunden. Vorhandene siehe list_projects()."}

    launcher = os.path.join(root, "gradlew")
    if os.path.exists(launcher):
        cmd = ["sh", launcher]
    elif shutil.which("gradle"):
        cmd = ["gradle"]
    else:
        return {"error": "Weder ein Gradle-Wrapper im Projekt noch ein globales gradle gefunden."}

    # --no-daemon: Der Gradle-Daemon würde zwischen Aufrufen weiterlaufen und
    # in diesem Container nur Speicher binden, ohne dass jemand ihn beendet.
    return _run(cmd + args.split() + ["--no-daemon"], cwd=root, timeout_seconds=timeout_seconds)


@mcp.tool()
def sdk_packages() -> dict:
    """Zeigt, welche Android-SDK-Pakete installiert sind (Plattformen,
    Build-Tools, …). Nützlich, um zu prüfen, ob eine bestimmte API-Ebene
    verfügbar ist, bevor du ein Projekt darauf umstellst.

    Nutze dieses Werkzeug auch, um die Frage "ist Android überhaupt
    verfügbar?" in EINEM Aufruf zu beantworten - statt in der Code-Sandbox
    nach SDK-Pfaden oder Umgebungsvariablen zu suchen.
    """
    return _run(["sdkmanager", "--list_installed"], cwd="/", timeout_seconds=120)


@mcp.tool()
def install_sdk_package(package: str, timeout_seconds: int = DEFAULT_TIMEOUT) -> dict:
    """Installiert ein weiteres Android-SDK-Paket nach, z. B.
    "platforms;android-35" oder "build-tools;35.0.0".

    :param package: SDK-Paketbezeichner wie von sdk_packages() angezeigt.
    :param timeout_seconds: Zeitlimit in Sekunden (Standard 600, maximal 1800).
    """
    # Nur Zeichen zulassen, die in SDK-Paketnamen vorkommen — der Wert geht
    # an einen Unterprozess, auch wenn hier keine Shell dazwischenliegt.
    if not re.match(r"^[A-Za-z0-9;._-]+$", package or ""):
        return {"error": "Ungültiger Paketbezeichner."}
    return _run(["sdkmanager", "--install", package], cwd="/", timeout_seconds=timeout_seconds)


if __name__ == "__main__":
    os.makedirs(WORKSPACE, exist_ok=True)
    mcp.run(transport="streamable-http", host=HOST, port=PORT)
