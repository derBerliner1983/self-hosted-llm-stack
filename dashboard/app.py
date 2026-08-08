#!/usr/bin/env python3
"""
Self-Hosted AI Stack — Dashboard

Ein winziger, abhängigkeitsfreier Statusserver (nur Python-Standardbibliothek).
Er liest den Docker-Socket (read-only gemountet) und liefert den Live-Status
der Stack-Container. Die statische Oberfläche (index.html) pollt /api/status
und zeigt an, was online ist, auf welchem Port es läuft, und verlinkt direkt
darauf.

This file is part of Self-Hosted AI Stack.
Licensed under the MIT License: https://opensource.org/licenses/MIT
"""

import datetime
import http.client
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DOCKER_SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
LISTEN_PORT = int(os.environ.get("DASHBOARD_PORT", "8080"))
HERE = os.path.dirname(os.path.abspath(__file__))

# Interne Adresse von Ollama im Docker-Netz (nicht der Host-Port aus PORT_OLLAMA
# — Container sprechen sich immer über den internen Port 11434 an).
OLLAMA_INTERNAL_URL = "http://ollama:11434"
LITELLM_INTERNAL_URL = "http://litellm:4000"
LITELLM_MASTER_KEY = os.environ.get("LITELLM_MASTER_KEY", "")
# Wie oft im Hintergrund geprüft wird, ob Ollama Modelle kennt, die LiteLLM
# noch nicht hat (z. B. per 'docker exec ollama ollama pull' oder CLI
# heruntergeladen, nicht über das Dashboard) — macht scripts/sync-ollama-
# models.sh für den Normalfall überflüssig, das bleibt als manueller Fallback.
MODEL_SYNC_INTERVAL = int(os.environ.get("DASHBOARD_MODEL_SYNC_INTERVAL", "60"))

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
        "container": "mcp",
        "label": "MCP Gateway",
        "desc": "Werkzeuge · Dateisystem, Web, GitHub",
        "icon": "🛠️",
        "port": None,
        "path": None,
    },
    {
        "container": "sandbox-mcp",
        "label": "Code-Sandbox",
        "desc": "run_python/run_shell · Wegwerf-Container",
        "icon": "🧪",
        "port": None,
        "path": None,
    },
    {
        "container": "mcpo",
        "label": "mcpo",
        "desc": "MCP → OpenAPI, für Open WebUI",
        "icon": "🔌",
        "port": None,
        "path": None,
    },
    {
        "container": "litellm-db",
        "label": "PostgreSQL",
        "desc": "Datenbank · pgvector",
        "icon": "🗄️",
        "port": None,
        "path": None,
    },
    {
        "container": "vault-bridge",
        "label": "Vault-Bridge",
        "desc": "Obsidian/Nextcloud → MCP-Dateisystem",
        "icon": "📓",
        "port": int(os.environ.get("PORT_VAULT_BRIDGE", "8700")),
        "path": "/",
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


# ── Ollama-Live-Status (geladene Modelle, RAM/VRAM, Aktivität) ──────────────
#
# Ollama hat keine "läuft gerade eine Anfrage"-API. Wir nähern das an: jede
# Anfrage an ein Modell verlängert dessen Keep-Alive (expires_at). Wenn sich
# expires_at seit dem letzten Poll verschoben hat, gab es zwischenzeitlich
# eine Anfrage -> "kürzlich aktiv". So sieht man näherungsweise, ob gerade
# etwas passiert, ohne dass Ollama das explizit anbieten muss.
_last_expires_at = {}   # Modellname -> zuletzt gesehenes expires_at (String)
_last_activity_ts = {}  # Modellname -> Unix-Timestamp der letzten Änderung


def _human_size(num_bytes):
    if not num_bytes:
        return "0 GB"
    gb = num_bytes / (1024 ** 3)
    return f"{gb:.1f} GB"


def build_ollama_status():
    try:
        req = urllib.request.Request(f"{OLLAMA_INTERNAL_URL}/api/ps")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return {"ok": False, "error": str(exc), "models": []}
    except json.JSONDecodeError as exc:
        return {"ok": False, "error": f"Ungültige Antwort von Ollama: {exc}", "models": []}

    now = time.time()
    models = []
    for m in data.get("models", []):
        name = m.get("name") or m.get("model") or "?"
        expires_at_raw = m.get("expires_at")
        seconds_left = None
        if expires_at_raw:
            try:
                exp = datetime.datetime.fromisoformat(expires_at_raw)
                seconds_left = max(0, int((exp - datetime.datetime.now(exp.tzinfo)).total_seconds()))
            except ValueError:
                pass

        changed = _last_expires_at.get(name) != expires_at_raw
        if changed:
            _last_expires_at[name] = expires_at_raw
            _last_activity_ts[name] = now
        last_activity = _last_activity_ts.get(name)
        seconds_since_activity = int(now - last_activity) if last_activity else None

        size = m.get("size", 0)
        size_vram = m.get("size_vram", 0)
        models.append(
            {
                "name": name,
                "size": _human_size(size),
                "size_vram": _human_size(size_vram),
                "fully_in_vram": bool(size) and size_vram >= size,
                "unloads_in_seconds": seconds_left,
                "recently_active": changed,
                "seconds_since_activity": seconds_since_activity,
            }
        )

    return {"ok": True, "models": models, "checked_at": now}


# ── Modelle laden / löschen / auflisten (schreibender Zugriff auf Ollama) ───
#
# Läuft über Ollamas eigene REST-API (/api/pull, /api/delete, /api/tags) —
# kein Docker-Socket-Zugriff nötig. Ollama akzeptiert im "name"-Feld sowohl
# normale Bibliotheksnamen (z. B. "llama3.1:8b") als auch Hugging-Face-
# Referenzen (z. B. "hf.co/user/repo:tag") über denselben Mechanismus, wir
# reichen also einfach durch, was eingegeben wurde.
#
# Mehrere Downloads gleichzeitig sind möglich: jeder Pull läuft in einem
# eigenen Hintergrund-Thread; _pull_jobs hält den Fortschritt pro Modellname.
_pull_jobs = {}
_pull_lock = threading.Lock()
_PULL_JOB_TTL = 600  # abgeschlossene Jobs nach 10 Min aus der Liste entfernen


def _prune_pull_jobs():
    now = time.time()
    with _pull_lock:
        stale = [
            name for name, j in _pull_jobs.items()
            if j.get("done") and (now - j.get("updated_at", now)) > _PULL_JOB_TTL
        ]
        for name in stale:
            del _pull_jobs[name]


def _set_job(name, **fields):
    with _pull_lock:
        job = _pull_jobs.setdefault(name, {})
        job.update(fields)
        job["updated_at"] = time.time()


def _pull_model(name):
    _set_job(
        name, status="wird gestartet …", completed=0, total=0, percent=None,
        done=False, error=None, started_at=time.time(),
    )
    try:
        payload = json.dumps({"name": name, "stream": True}).encode()
        req = urllib.request.Request(
            f"{OLLAMA_INTERNAL_URL}/api/pull", data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=3600) as resp:
            while True:
                line = resp.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if "error" in obj:
                    _set_job(name, status=obj["error"], done=True, error=obj["error"])
                    return
                status = obj.get("status", "")
                total = obj.get("total")
                completed = obj.get("completed")
                percent = None
                if total and completed is not None and total > 0:
                    percent = round(completed / total * 100, 1)
                fields = {"status": status}
                if total is not None:
                    fields["total"] = total
                if completed is not None:
                    fields["completed"] = completed
                if percent is not None:
                    fields["percent"] = percent
                if status == "success":
                    fields["done"] = True
                _set_job(name, **fields)
        if _pull_jobs.get(name, {}).get("done") and not _pull_jobs[name].get("error"):
            # Sofort mit LiteLLM abgleichen statt bis zum nächsten Intervall-
            # Tick zu warten — sonst müsste man nach dem Laden bis zu
            # MODEL_SYNC_INTERVAL Sekunden warten, bis das Modell in Open
            # WebUI (über LiteLLM) auftaucht.
            threading.Thread(target=_run_sync_and_update_state, daemon=True).start()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        _set_job(name, status=f"Fehler {exc.code}", done=True, error=body or str(exc))
    except Exception as exc:  # noqa: BLE001 - jeder Fehler soll den Job sauber beenden
        _set_job(name, status="Fehler", done=True, error=str(exc))


def build_ollama_models():
    try:
        req = urllib.request.Request(f"{OLLAMA_INTERNAL_URL}/api/tags")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return {"ok": False, "error": str(exc), "models": []}
    except json.JSONDecodeError as exc:
        return {"ok": False, "error": f"Ungültige Antwort von Ollama: {exc}", "models": []}

    models = [
        {
            "name": m.get("name") or m.get("model") or "?",
            "size": _human_size(m.get("size", 0)),
            "modified_at": m.get("modified_at"),
        }
        for m in data.get("models", [])
    ]
    return {"ok": True, "models": models}


def delete_ollama_model(name):
    try:
        payload = json.dumps({"name": name}).encode()
        req = urllib.request.Request(
            f"{OLLAMA_INTERNAL_URL}/api/delete", data=payload,
            headers={"Content-Type": "application/json"}, method="DELETE",
        )
        with urllib.request.urlopen(req, timeout=15):
            return {"ok": True}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        return {"ok": False, "error": f"{exc.code}: {body or exc.reason}"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)}


# ── Automatische LiteLLM-Registrierung (WebUI/Claude/... "verdrahten") ─────
#
# Damit jedes bei Ollama installierte Modell automatisch bei LiteLLM auftaucht
# (und damit in Open WebUI über die MCP-fähige Verbindung nutzbar ist), ohne
# jedes Mal manuell scripts/sync-ollama-models.sh auszuführen: ein Hintergrund-
# Thread gleicht in Intervallen ab, welche Ollama-Modelle LiteLLM noch nicht
# kennt, und trägt sie automatisch ein (gleiche Logik/API wie das Skript,
# nur fortlaufend statt manuell angestoßen). Läuft nur, wenn LITELLM_MASTER_KEY
# gesetzt ist (siehe docker-compose.rocm.yml).
_sync_lock = threading.Lock()
_sync_state = {
    "enabled": bool(LITELLM_MASTER_KEY),
    "last_run": None,
    "added": 0,
    "known": 0,
    "error": None,
}


def _litellm_api(path, method="GET", payload=None, timeout=15):
    req = urllib.request.Request(
        f"{LITELLM_INTERNAL_URL}{path}", method=method,
        headers={"Authorization": f"Bearer {LITELLM_MASTER_KEY}", "Content-Type": "application/json"},
    )
    if payload is not None:
        req.data = json.dumps(payload).encode()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


def sync_models_with_litellm():
    """Trägt alle in Ollama installierten, bei LiteLLM noch fehlenden Modelle
    dort ein (model_name "ollama/<name>", api_base auf den Ollama-Container).
    Idempotent: bereits vorhandene werden übersprungen. Gibt (added, known,
    error) zurück; error ist None bei Erfolg (auch wenn added == 0)."""
    if not LITELLM_MASTER_KEY:
        return 0, 0, "LITELLM_MASTER_KEY nicht gesetzt — automatische Registrierung deaktiviert."

    try:
        req = urllib.request.Request(f"{OLLAMA_INTERNAL_URL}/api/tags")
        with urllib.request.urlopen(req, timeout=10) as resp:
            tags = json.loads(resp.read())
        ollama_models = {
            m.get("name") or m.get("model")
            for m in tags.get("models", [])
            if m.get("name") or m.get("model")
        }
    except Exception as exc:  # noqa: BLE001
        return 0, 0, f"Ollama nicht erreichbar: {exc}"

    try:
        data = _litellm_api("/v1/models")
        existing = {
            m.get("id", "")[len("ollama/"):]
            for m in data.get("data", [])
            if m.get("id", "").startswith("ollama/")
        }
    except Exception as exc:  # noqa: BLE001
        return 0, 0, f"LiteLLM nicht erreichbar: {exc}"

    added = 0
    for name in sorted(ollama_models - existing):
        try:
            _litellm_api("/model/new", "POST", {
                "model_name": f"ollama/{name}",
                "litellm_params": {"model": f"ollama/{name}", "api_base": OLLAMA_INTERNAL_URL},
            })
            added += 1
        except Exception as exc:  # noqa: BLE001
            print(f"! LiteLLM-Registrierung fehlgeschlagen für ollama/{name}: {exc}")

    return added, len(ollama_models), None


def _run_sync_and_update_state():
    added, known, error = sync_models_with_litellm()
    with _sync_lock:
        _sync_state.update(
            enabled=bool(LITELLM_MASTER_KEY),
            last_run=time.time(),
            added=_sync_state["added"] + added,
            known=known,
            error=error,
        )


def _model_sync_loop():
    while True:
        _run_sync_and_update_state()
        time.sleep(MODEL_SYNC_INTERVAL)


def build_sync_status():
    with _sync_lock:
        return dict(_sync_state)


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
        if self.path.startswith("/api/ollama/status"):
            self._send(200, json.dumps(build_ollama_status()), "application/json")
            return
        if self.path.startswith("/api/ollama/models"):
            self._send(200, json.dumps(build_ollama_models()), "application/json")
            return
        if self.path.startswith("/api/ollama/pulls"):
            _prune_pull_jobs()
            with _pull_lock:
                snapshot = {name: dict(job) for name, job in _pull_jobs.items()}
            self._send(200, json.dumps(snapshot), "application/json")
            return
        if self.path.startswith("/api/ollama/sync"):
            self._send(200, json.dumps(build_sync_status()), "application/json")
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

    def do_POST(self):  # noqa: N802 - vorgegebene Signatur
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            body = {}
        name = str(body.get("model") or "").strip()

        if self.path == "/api/ollama/pull":
            if not name:
                self._send(400, json.dumps({"ok": False, "error": "Kein Modellname angegeben."}), "application/json")
                return
            with _pull_lock:
                existing = _pull_jobs.get(name)
            if existing and not existing.get("done"):
                self._send(200, json.dumps({"ok": True, "note": "Download läuft bereits."}), "application/json")
                return
            threading.Thread(target=_pull_model, args=(name,), daemon=True).start()
            self._send(200, json.dumps({"ok": True}), "application/json")
            return

        if self.path == "/api/ollama/delete":
            if not name:
                self._send(400, json.dumps({"ok": False, "error": "Kein Modellname angegeben."}), "application/json")
                return
            result = delete_ollama_model(name)
            self._send(200 if result["ok"] else 400, json.dumps(result), "application/json")
            return

        self._send(404, json.dumps({"ok": False, "error": "not found"}), "application/json")

    def log_message(self, *args):  # Logs ruhig halten
        return


def main():
    if LITELLM_MASTER_KEY:
        threading.Thread(target=_model_sync_loop, daemon=True).start()
        print(f"Automatische LiteLLM-Modellregistrierung aktiv (alle {MODEL_SYNC_INTERVAL}s).")
    else:
        print("LITELLM_MASTER_KEY nicht gesetzt — automatische LiteLLM-Registrierung deaktiviert.")
    httpd = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"Dashboard läuft auf Port {LISTEN_PORT} (Docker-Socket: {DOCKER_SOCK})")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
