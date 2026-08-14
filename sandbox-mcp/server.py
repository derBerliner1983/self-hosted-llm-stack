#!/usr/bin/env python3
"""
Code-Sandbox — MCP-Server für Self-Hosted AI Stack.

Gibt dem LLM (über LiteLLM) zwei Werkzeuge:
  - run_python(code):  führt Python-Code aus
  - run_shell(command): führt einen Shell-Befehl aus

Jeder Aufruf startet einen KOMPLETT NEUEN, isolierten Wegwerf-Container
(kein Netzwerk, read-only Dateisystem, Ressourcen-Limits, kein root, alle
Capabilities entfernt) und löscht ihn danach sofort wieder — es gibt also
nie einen Zustand zum "Zurücksetzen": jeder Lauf startet garantiert frisch.

Gedacht dafür, dass das Modell selbst geschriebenen Code testen, Fehler
in der Ausgabe erkennen und die Lösung iterativ korrigieren kann, bevor
es eine Antwort gibt.

Braucht Zugriff auf den Docker-Socket (mächtig — siehe README, Abschnitt
"Code-Sandbox"). Läuft absichtlich nur intern im Docker-Netz, ohne
Host-Port.

This file is part of Self-Hosted AI Stack. MIT License.
"""

import os
import uuid

import docker
from docker.errors import DockerException, NotFound
from mcp.server.mcpserver import MCPServer

RUNNER_IMAGE = os.environ.get("SANDBOX_IMAGE", "python:3.12-slim")
DEFAULT_TIMEOUT = int(os.environ.get("SANDBOX_DEFAULT_TIMEOUT", "15"))
MAX_TIMEOUT = int(os.environ.get("SANDBOX_MAX_TIMEOUT", "60"))
MEM_LIMIT = os.environ.get("SANDBOX_MEM_LIMIT", "256m")
# Größe des beschreibbaren /tmp im Wegwerf-Container (der Rest des
# Dateisystems ist read-only). Für reines Python reichen 64 MB; Compiler
# (javac, go build, g++) brauchen deutlich mehr Platz für Zwischenstände —
# siehe README, Abschnitt "Mehr Sprachen in der Sandbox".
TMPFS_SIZE = os.environ.get("SANDBOX_TMPFS_SIZE", "64m")
NETWORK_MODE = os.environ.get("SANDBOX_NETWORK", "none")  # "none" = kein Internetzugriff
MAX_OUTPUT_CHARS = 20_000

# HOST/PORT werden erst bei .run() übergeben (MCPServer nimmt sie nicht im
# Konstruktor, sondern als Kwargs für den jeweiligen Transport entgegen).
HOST = os.environ.get("FASTMCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("FASTMCP_PORT", "8000"))

mcp = MCPServer("Code-Sandbox")

# Docker-Client bewusst lazy (erst beim ersten Werkzeug-Aufruf), nicht beim
# Import — sonst würde ein kurzzeitig noch nicht bereiter Docker-Socket beim
# Containerstart den ganzen MCP-Server sofort abstürzen lassen.
_docker_client = None


def _get_docker():
    global _docker_client
    if _docker_client is None:
        _docker_client = docker.from_env()
    return _docker_client


def _ensure_runner_image() -> None:
    _docker = _get_docker()
    try:
        _docker.images.get(RUNNER_IMAGE)
    except NotFound:
        _docker.images.pull(RUNNER_IMAGE)


def _run_in_sandbox(cmd: list[str], timeout_seconds: int) -> dict:
    """Startet einen frischen, isolierten Wegwerf-Container, führt cmd aus,
    sammelt die Ausgabe ein und entfernt den Container garantiert wieder."""
    timeout_seconds = max(1, min(timeout_seconds, MAX_TIMEOUT))
    name = f"ai-stack-sandbox-{uuid.uuid4().hex[:12]}"
    container = None
    try:
        _ensure_runner_image()
        container = _get_docker().containers.run(
            image=RUNNER_IMAGE,
            command=cmd,
            name=name,
            detach=True,
            network_mode=NETWORK_MODE,
            mem_limit=MEM_LIMIT,
            nano_cpus=1_000_000_000,  # 1 CPU-Kern
            pids_limit=128,
            read_only=True,
            tmpfs={"/tmp": f"rw,size={TMPFS_SIZE},mode=1777"},
            working_dir="/tmp",
            user="65534:65534",  # nobody:nogroup — kein root
            cap_drop=["ALL"],
            security_opt=["no-new-privileges:true"],
        )
        try:
            result = container.wait(timeout=timeout_seconds)
            exit_code = result.get("StatusCode", -1)
            timed_out = False
        except Exception:
            timed_out = True
            exit_code = None

        try:
            output = container.logs(stdout=True, stderr=True).decode("utf-8", errors="replace")
        except Exception:
            output = ""

        if len(output) > MAX_OUTPUT_CHARS:
            output = output[:MAX_OUTPUT_CHARS] + "\n… (Ausgabe gekürzt)"

        if timed_out:
            return {
                "output": output,
                "exit_code": None,
                "timed_out": True,
                "note": f"Zeitlimit von {timeout_seconds}s überschritten — Code lief vermutlich in eine Endlosschleife.",
            }
        return {"output": output, "exit_code": exit_code, "timed_out": False}
    except DockerException as exc:
        return {"output": "", "exit_code": None, "timed_out": False, "error": f"Sandbox-Fehler: {exc}"}
    finally:
        if container is not None:
            try:
                container.remove(force=True)
            except Exception:
                pass


@mcp.tool()
def run_python(code: str, timeout_seconds: int = DEFAULT_TIMEOUT) -> dict:
    """Führt Python-Code in einer isolierten, einmaligen Wegwerf-Sandbox aus
    (kein Netzwerk, keine Verbindung zum restlichen Stack, wird danach sofort
    gelöscht) und gibt die kombinierte stdout/stderr-Ausgabe sowie den
    Exit-Code zurück.

    Nutze dieses Werkzeug IMMER, um selbst geschriebenen Code zu testen,
    bevor du ihn als Antwort ausgibst: führe den Code aus, prüfe die Ausgabe
    auf Fehler/Tracebacks, korrigiere den Code bei Bedarf und teste erneut.

    Kein Netzwerk (pip install schlägt fehl), kein Zustand zwischen
    Aufrufen, kein Android SDK - für Android gibt es eigene Werkzeuge in
    einem anderen Dienst. Siehe run_shell für Details.

    :param code: Der auszuführende Python-Code.
    :param timeout_seconds: Zeitlimit in Sekunden (Standard 15, maximal 60).
    """
    return _run_in_sandbox(["python3", "-c", code], timeout_seconds)


@mcp.tool()
def run_shell(command: str, timeout_seconds: int = DEFAULT_TIMEOUT) -> dict:
    """Führt einen Shell-Befehl in derselben isolierten Wegwerf-Sandbox aus
    wie run_python (kein Netzwerk, wird danach sofort gelöscht) und gibt die
    kombinierte stdout/stderr-Ausgabe sowie den Exit-Code zurück.

    WICHTIG - was hier NICHT vorhanden ist, damit du nicht danach suchst:

    - KEIN Android SDK, kein Gradle, kein adb, kein $ANDROID_HOME. Für alles
      rund um Android gibt es eigene Werkzeuge (create_project, gradle,
      sdk_packages, ...) in einem anderen Dienst. Suche Android NICHT hier.
    - KEIN Netzwerk: apt-get/pip install/npm install/curl schlagen immer
      fehl. Nur was im Image liegt, ist nutzbar.
    - KEIN Zustand zwischen Aufrufen: Jeder Aufruf startet einen frischen
      Container. In einem früheren Aufruf angelegte Dateien sind weg.
      Schreibe und nutze eine Datei deshalb IMMER im selben Aufruf
      (mit && verketten).
    - KEIN Zugriff auf den Vault oder andere Stack-Verzeichnisse. Dateien
      liest/schreibst du mit den Dateisystem-Werkzeugen, nicht hier.

    Wenn ein Befehl "not found" meldet, ist das Programm schlicht nicht
    installiert - probiere dann NICHT dutzende Varianten und Pfade durch,
    sondern sage dem Nutzer, dass es fehlt.

    :param command: Der auszuführende Shell-Befehl.
    :param timeout_seconds: Zeitlimit in Sekunden (Standard 15, maximal 60).
    """
    return _run_in_sandbox(["sh", "-c", command], timeout_seconds)


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host=HOST, port=PORT)
