#!/usr/bin/env python3
"""
Self-Hosted AI Stack — Dashboard (Apple-Design)

Ein winziger, abhängigkeitsfreier Statusserver (nur Python-Standardbibliothek).
Er liest den Docker-Socket (read-only gemountet) und liefert den Live-Status
der Stack-Container. Die statische Oberfläche (index.html) pollt /api/status
und zeigt an, was online ist, auf welchem Port es läuft, und verlinkt direkt
darauf.

This file is part of Self-Hosted AI Stack.
Licensed under the MIT License: https://opensource.org/licenses/MIT
"""

import http.client
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DOCKER_SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
LISTEN_PORT = int(os.environ.get("DASHBOARD_PORT", "8080"))
HERE = os.path.dirname(os.path.abspath(__file__))

# Bekannte Dienste des Stacks: Container-Name -> Anzeige.
# "port" ist der Host-Port (aus Sicht des Browsers), "path" der Link-Pfad.
SERVICES = [
    {
        "container": "open-webui",
        "label": "Open WebUI",
        "desc": "Chat-Oberfläche",
        "icon": "💬",
        "port": int(os.environ.get("PORT_WEBUI", "3001")),
        "path": "/",
    },
    {
        "container": "litellm",
        "label": "LiteLLM",
        "desc": "AI-Gateway · Admin-UI",
        "icon": "🚦",
        "port": int(os.environ.get("PORT_LITELLM", "4000")),
        "path": "/ui",
    },
    {
        "container": "ollama",
        "label": "Ollama",
        "desc": "LLM-Engine (ROCm)",
        "icon": "🧠",
        "port": int(os.environ.get("PORT_OLLAMA", "11434")),
        "path": "/",
    },
    {
        "container": "whisper",
        "label": "Whisper",
        "desc": "Sprache → Text",
        "icon": "🎤",
        "port": int(os.environ.get("PORT_WHISPER", "9000")),
        "path": "/docs",
    },
    {
        "container": "embeddings",
        "label": "Embeddings",
        "desc": "Text → Vektoren",
        "icon": "🔎",
        "port": int(os.environ.get("PORT_EMBEDDINGS", "8000")),
        "path": "/docs",
    },
    {
        "container": "litellm-db",
        "label": "PostgreSQL",
        "desc": "Datenbank · pgvector",
        "icon": "🗄️",
        "port": None,
        "path": None,
    },
]


class _UnixHTTPConnection(http.client.HTTPConnection):
    """HTTP über einen Unix-Domain-Socket (für den Docker-Socket)."""

    def __init__(self, path):
        super().__init__("localhost")
        self._unix_path = path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(self._unix_path)
        self.sock = s


def _docker_get(path):
    conn = _UnixHTTPConnection(DOCKER_SOCK)
    try:
        conn.request("GET", path)
        resp = conn.getresponse()
        body = resp.read()
        if resp.status != 200:
            return None
        return json.loads(body)
    finally:
        conn.close()


def _container_index():
    """Map: Container-Name (ohne führenden '/') -> Container-Objekt."""
    containers = _docker_get("/v1.41/containers/json?all=1") or []
    index = {}
    for c in containers:
        for name in c.get("Names", []):
            index[name.lstrip("/")] = c
    return index


def _state_for(container):
    if container is None:
        return {"state": "absent", "health": None, "status": "nicht vorhanden"}
    state = container.get("State", "unknown")  # running, exited, ...
    status = container.get("Status", "")       # z. B. "Up 3 minutes (healthy)"
    health = None
    if "(healthy)" in status:
        health = "healthy"
    elif "(unhealthy)" in status:
        health = "unhealthy"
    elif "(health: starting)" in status:
        health = "starting"
    return {"state": state, "health": health, "status": status}


def build_status():
    try:
        index = _container_index()
        docker_ok = True
    except Exception as exc:  # noqa: BLE001 - Socket/Docker evtl. nicht erreichbar
        index = {}
        docker_ok = False
        docker_err = str(exc)

    services = []
    for svc in SERVICES:
        st = _state_for(index.get(svc["container"]))
        running = st["state"] == "running"
        online = running and st["health"] in (None, "healthy")
        services.append(
            {
                "container": svc["container"],
                "label": svc["label"],
                "desc": svc["desc"],
                "icon": svc["icon"],
                "port": svc["port"],
                "path": svc["path"],
                "state": st["state"],
                "health": st["health"],
                "status": st["status"],
                "online": online,
                "running": running,
            }
        )

    result = {"services": services, "docker_ok": docker_ok}
    if not docker_ok:
        result["docker_error"] = docker_err
    return result


class Handler(BaseHTTPRequestHandler):
    server_version = "AIStackDashboard/1.0"

    def _send(self, code, body, ctype):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 - vorgegebene Signatur
        if self.path.startswith("/api/status"):
            self._send(200, json.dumps(build_status()), "application/json")
            return
        if self.path.startswith("/healthz"):
            self._send(200, "ok", "text/plain")
            return
        # Alles andere -> die statische Oberfläche.
        try:
            with open(os.path.join(HERE, "index.html"), "rb") as fh:
                self._send(200, fh.read(), "text/html; charset=utf-8")
        except OSError:
            self._send(404, "not found", "text/plain")

    def log_message(self, *args):  # Logs ruhig halten
        return


def main():
    httpd = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"Dashboard läuft auf Port {LISTEN_PORT} (Docker-Socket: {DOCKER_SOCK})")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
