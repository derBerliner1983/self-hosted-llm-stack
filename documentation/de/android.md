# Android-Entwicklung

Android-Projekte anlegen, bauen und testen lassen.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/android.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · **Android-Entwicklung** · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Android-Entwicklung (`android-mcp`)

Für Android reicht die Wegwerf-Sandbox nicht: Gradle lädt Abhängigkeiten aus dem Netz, ein Build dauert Minuten statt Sekunden, und ohne persistenten Cache würde jeder Lauf wieder bei null anfangen. Deshalb bringt der Stack dafür einen **eigenen Dienst** mit (`android-mcp/`), in dem die Builds **direkt im Container** laufen — was ihm nebenbei den Docker-Socket-Zugriff erspart, den die Code-Sandbox braucht.

Enthalten: **JDK 21**, **Android SDK** (Kommandozeilen-Werkzeuge, Platform-Tools, Build-Tools, Plattform android-34) und **Gradle**. Werkzeuge für das Modell:

| Werkzeug | Zweck |
|---|---|
| `list_projects()` | Projekte im Arbeitsbereich auflisten |
| `create_project(name, package_name)` | Neues, baubares Java-Gradle-Projekt anlegen (Manifest, MainActivity, Beispieltest, Gradle-Wrapper) |
| `gradle(project, args)` | Gradle-Aufgabe ausführen — `assembleDebug`, `test`, `clean`, `tasks` … |
| `sdk_packages()` | Installierte SDK-Pakete anzeigen |
| `install_sdk_package(paket)` | Weiteres SDK-Paket nachinstallieren, z. B. `platforms;android-35` |

Der Quelltext liegt im Volume `android-workspace`, das **auch im `mcp`-Container** unter `/workspace` eingehängt ist. Dadurch kann das Modell den Code mit den **Dateisystem-Werkzeugen** bearbeiten und ihn mit `gradle` bauen — Schreiben und Bauen greifen auf dieselben Dateien zu.

**Typischer Ablauf im Chat:** „Leg ein Android-Projekt `MeineApp` an" → `create_project` → Modell bearbeitet `MainActivity.java` per Dateisystem-Werkzeug → „bau das mal" → `gradle(project="MeineApp", args="assembleDebug")` → bei Fehlern liest das Modell die Gradle-Ausgabe und korrigiert selbst.

**Bauen und starten:**

```bash
docker compose -f docker-compose.rocm.yml up -d --build android-mcp
./scripts/wire-mcp.sh    # trägt /workspace beim Dateisystem-Werkzeug nach
```

> ⚠️ **Das Image ist groß (~6–8 GB) und der erste Bau dauert entsprechend lange** (Android SDK). Auch der erste Gradle-Lauf eines Projekts zieht Gradle und alle Abhängigkeiten — danach greift der Cache im Volume `android-gradle`. Wer keine Android-Entwicklung braucht, kann den Dienst ersatzlos streichen (dann auch den `android_build`-Eintrag aus `mcpo/config.template.json` entfernen).

**Grenzen:**

- **Kein Emulator, keine App-Ausführung.** Gebaut, kompiliert und per Unittest geprüft wird im Container; ausprobieren musst du die APK auf einem echten Gerät. Ein Emulator bräuchte `/dev/kvm` im Container und ist erfahrungsgemäß fragil.
- **Kein `adb`-Zugriff auf deine Geräte** — die hängen an deinem Rechner, nicht am Server.
- **Netzwerkzugriff ist hier Absicht** (Gradle braucht ihn) — anders als bei der Code-Sandbox. Gradle-Build-Skripte sind ausführbarer Code; dieser Dienst ist damit ähnlich mächtig wie die Sandbox, nur eben mit Internet. Er ist deshalb wie die Sandbox **nur intern** erreichbar, ohne veröffentlichten Port.
- **Die Projektvorlage ist bewusst minimal** (Java, kein Kotlin/Compose) — weniger Versionsabhängigkeiten zwischen Gradle, AGP und Kotlin, die zueinander passen müssen. Kotlin/Compose lassen sich im Projekt selbst nachrüsten.

Konfigurierbar über `.env`: `ANDROID_DEFAULT_TIMEOUT` (Standard `600` s), `ANDROID_MAX_TIMEOUT` (`1800` s), `ANDROID_COMPILE_SDK` (`34`), `ANDROID_MIN_SDK` (`24`). SDK-/Gradle-/AGP-Versionen stehen als Build-Argumente in `android-mcp/Dockerfile`.
