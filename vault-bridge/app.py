#!/usr/bin/env python3
"""
Self-Hosted AI Stack — Vault-Bridge

Verbindet einen auf Nextcloud gehosteten Obsidian-Vault (per WebDAV) mit dem
MCP Gateway, damit ALLE an LiteLLM angebundenen Clients (Open WebUI, künftig
z. B. Claude) das eigene Wissen als Werkzeug nutzen können — ohne KI in
Obsidian selbst einzubauen ("Version 2": die KI greift auf das Gehirn zu,
statt dass das Gehirn die KI enthält).

Architektur:
  Nextcloud (WebDAV) --rclone sync--> vault-data (Docker-Volume, hier :rw)
                                            |
                                            +--:ro--> mcp-Container
                                                       (MCP_FILESYSTEM_DIRS)

Diese Bridge selbst spricht kein MCP — sie hält nur eine lokale Kopie des
Vaults aktuell. Sobald die Verbindung erfolgreich ist, sieht das MCP Gateway
das Verzeichnis automatisch (gleiches Volume, kein Neustart nötig).

Kein Framework, keine Zusatzabhängigkeiten außer dem rclone-Binary (im
Dockerfile installiert) — bewusst im gleichen minimalistischen Stil wie
dashboard/app.py gehalten.

⚠️  Sicherheit: Das Nextcloud-App-Passwort wird nie im Klartext auf Platte
    abgelegt. Es wird vor dem Schreiben in rclone.conf mit `rclone obscure`
    verschleiert — das ist KEINE echte Verschlüsselung, nur Schutz vor
    zufälligem Mitlesen (Standard-rclone-Praxis). Nutze unbedingt ein
    dediziertes Nextcloud-App-Passwort (Profil -> Sicherheit), niemals das
    Hauptpasswort.

This file is part of Self-Hosted AI Stack.
Licensed under the MIT License: https://opensource.org/licenses/MIT
"""

import datetime
import json
import os
import subprocess
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
LISTEN_PORT = int(os.environ.get("VAULT_BRIDGE_PORT", "8080"))

DATA_DIR = os.environ.get("VAULT_BRIDGE_DATA_DIR", "/data")
VAULT_DIR = os.environ.get("VAULT_BRIDGE_VAULT_DIR", "/vault")
CONFIG_FILE = os.path.join(DATA_DIR, "config.json")
RCLONE_CONF = os.path.join(DATA_DIR, "rclone.conf")
RCLONE_REMOTE = "nextcloud"

_state_lock = threading.Lock()
_wake_event = threading.Event()

_DEFAULT_STATE = {
    "connected": False,
    "url": "",
    "username": "",
    "vault_path": "",
    "interval_minutes": 60,
    "last_sync": None,
    "last_status": None,   # "ok" | "error" | None (noch nie synchronisiert)
    "last_error": "",
    "syncing": False,
}


def _now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def _load_state():
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as fh:
            saved = json.load(fh)
    except (OSError, json.JSONDecodeError):
        saved = {}
    state = dict(_DEFAULT_STATE)
    state.update({k: v for k, v in saved.items() if k in _DEFAULT_STATE})
    state["syncing"] = False  # nie als "läuft" starten, egal was gespeichert war
    return state


def _save_state(state):
    os.makedirs(DATA_DIR, exist_ok=True)
    persisted = {k: v for k, v in state.items() if k != "syncing"}
    tmp = CONFIG_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(persisted, fh, indent=2, ensure_ascii=False)
    os.replace(tmp, CONFIG_FILE)


def _update_state(**changes):
    with _state_lock:
        state = _load_state()
        state.update(changes)
        _save_state(state)
        return state


def _get_state():
    with _state_lock:
        return _load_state()


# ── WebDAV-URL für Nextcloud aufbauen ───────────────────────────────────────
#
# Verifiziert gegen die offizielle Nextcloud-Doku: Der für Drittanbieter-Apps
# vorgesehene, aktuelle Endpunkt ist  {server}/remote.php/dav/files/{user}/
# (nicht der veraltete Alias remote.php/webdav/). App-Passwörter (Profil ->
# Sicherheit) werden dafür ausdrücklich empfohlen und unterstützt.
def build_webdav_url(base_url, username, vault_path):
    base = (base_url or "").strip().rstrip("/")
    if not base:
        raise ValueError("Nextcloud-Server-URL fehlt.")
    if not base.startswith("http://") and not base.startswith("https://"):
        base = "https://" + base
    user_enc = urllib.parse.quote(username.strip(), safe="")
    path = (vault_path or "").strip().strip("/")
    if path:
        path_enc = "/".join(urllib.parse.quote(seg, safe="") for seg in path.split("/"))
        return f"{base}/remote.php/dav/files/{user_enc}/{path_enc}/"
    return f"{base}/remote.php/dav/files/{user_enc}/"


def _rclone_obscure(password):
    result = subprocess.run(
        ["rclone", "obscure", password],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or "rclone obscure fehlgeschlagen").strip())
    return result.stdout.strip()


def _write_rclone_conf(url, username, obscured_password):
    os.makedirs(DATA_DIR, exist_ok=True)
    conf = (
        f"[{RCLONE_REMOTE}]\n"
        f"type = webdav\n"
        f"url = {url}\n"
        f"vendor = nextcloud\n"
        f"user = {username}\n"
        f"pass = {obscured_password}\n"
    )
    with open(RCLONE_CONF, "w", encoding="utf-8") as fh:
        fh.write(conf)
    os.chmod(RCLONE_CONF, 0o600)


def do_sync():
    """Einen rclone-Sync ausführen (Nextcloud -> lokales vault-data-Volume).

    Read-only in eine Richtung gedacht: die Bridge schreibt, das MCP Gateway
    mountet das Ziel-Volume separat als :ro. Läuft nur einmal gleichzeitig.
    """
    with _state_lock:
        state = _load_state()
        if state["syncing"] or not state["connected"]:
            return
        state["syncing"] = True
        _save_state(state)

    try:
        os.makedirs(VAULT_DIR, exist_ok=True)
        result = subprocess.run(
            [
                "rclone", "sync", f"{RCLONE_REMOTE}:", VAULT_DIR,
                "--config", RCLONE_CONF,
                "--fast-list",
                "--create-empty-src-dirs",
            ],
            capture_output=True, text=True, timeout=3600,
        )
        if result.returncode == 0:
            _update_state(last_sync=_now_iso(), last_status="ok", last_error="")
        else:
            err = (result.stderr or result.stdout or "unbekannter Fehler").strip()
            _update_state(last_sync=_now_iso(), last_status="error", last_error=err[-2000:])
    except subprocess.TimeoutExpired:
        _update_state(last_sync=_now_iso(), last_status="error",
                       last_error="Zeitüberschreitung beim Sync (>60 Minuten).")
    except Exception as exc:  # noqa: BLE001 - jeden Fehler sichtbar melden statt crashen
        _update_state(last_sync=_now_iso(), last_status="error", last_error=str(exc))
    finally:
        with _state_lock:
            state = _load_state()
            state["syncing"] = False
            _save_state(state)


def _sync_loop():
    while True:
        state = _get_state()
        if state["connected"]:
            do_sync()
            interval = max(1, int(state.get("interval_minutes") or 60))
        else:
            interval = 5
        _wake_event.wait(timeout=interval * 60)
        _wake_event.clear()


def connect(payload):
    url_in = str(payload.get("url") or "").strip()
    username = str(payload.get("username") or "").strip()
    app_password = str(payload.get("app_password") or "")
    vault_path = str(payload.get("vault_path") or "").strip()
    try:
        interval_minutes = int(payload.get("interval_minutes") or 60)
    except (TypeError, ValueError):
        interval_minutes = 60
    interval_minutes = max(1, min(interval_minutes, 24 * 60))

    if not url_in or not username or not app_password:
        return {"ok": False, "error": "Server-URL, Benutzername und App-Passwort werden benötigt."}

    try:
        webdav_url = build_webdav_url(url_in, username, vault_path)
        obscured = _rclone_obscure(app_password)
        _write_rclone_conf(webdav_url, username, obscured)
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)}

    _update_state(
        connected=True,
        url=url_in,
        username=username,
        vault_path=vault_path,
        interval_minutes=interval_minutes,
        last_status=None,
        last_error="",
    )
    threading.Thread(target=do_sync, daemon=True).start()
    _wake_event.set()
    return {"ok": True, "state": _get_state()}


def disconnect():
    _update_state(connected=False, last_status=None, last_error="")
    try:
        if os.path.exists(RCLONE_CONF):
            os.remove(RCLONE_CONF)
    except OSError:
        pass
    return {"ok": True, "state": _get_state()}


def sync_now():
    state = _get_state()
    if not state["connected"]:
        return {"ok": False, "error": "Nicht verbunden."}
    if state["syncing"]:
        return {"ok": True, "note": "Sync läuft bereits."}
    threading.Thread(target=do_sync, daemon=True).start()
    _wake_event.set()
    return {"ok": True}


class Handler(BaseHTTPRequestHandler):
    server_version = "VaultBridge/1.0"

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
        if self.path.startswith("/api/config") or self.path.startswith("/api/status"):
            self._send(200, json.dumps(_get_state()), "application/json")
            return
        if self.path.startswith("/healthz"):
            self._send(200, "ok", "text/plain")
            return
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

        if self.path == "/api/connect":
            result = connect(body)
            self._send(200 if result.get("ok") else 400, json.dumps(result), "application/json")
            return
        if self.path == "/api/disconnect":
            result = disconnect()
            self._send(200, json.dumps(result), "application/json")
            return
        if self.path == "/api/sync-now":
            result = sync_now()
            self._send(200 if result.get("ok") else 400, json.dumps(result), "application/json")
            return

        self._send(404, json.dumps({"ok": False, "error": "not found"}), "application/json")

    def log_message(self, *args):  # Logs ruhig halten
        return


def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(VAULT_DIR, exist_ok=True)
    threading.Thread(target=_sync_loop, daemon=True).start()
    httpd = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"Vault-Bridge läuft auf Port {LISTEN_PORT} (Ziel: {VAULT_DIR})")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
