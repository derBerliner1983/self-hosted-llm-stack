#!/usr/bin/env python3
"""
Self-Hosted AI Stack — Austausch-Ablage (Exchange-Bridge)

Ein Ordner, den zwei Seiten gleichzeitig sehen:

  - Du im Browser: Dateien hochladen, herunterladen, ansehen, löschen.
  - Das LLM über das Dateisystem-Werkzeug (mcp_gateway, MCP_FILESYSTEM_DIRS
    enthält denselben Pfad): lesen und schreiben, genauso wie beim Vault.

Bewusst NICHT der Vault — der bleibt Wissensdatenbank, keine Ablage für
Baubeiläufigkeiten wie eine fertig gebaute APK oder Skripte zum Testen.

Bewusst kein Framework, keine Zusatzabhängigkeiten (derselbe minimalistische
Stil wie dashboard/app.py und vault-bridge/app.py) — nur die Python-
Standardbibliothek, per Hand geparstes multipart/form-data eingeschlossen.

This file is part of Self-Hosted AI Stack.
Licensed under the MIT License: https://opensource.org/licenses/MIT
"""

import datetime
import json
import os
import re
import secrets
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
EXCHANGE_DIR = os.environ.get("EXCHANGE_DIR", "/exchange")
LISTEN_PORT = int(os.environ.get("EXCHANGE_BRIDGE_PORT", "8080"))
AUTH_USER = os.environ.get("EXCHANGE_USER", "admin")
AUTH_PASSWORD = os.environ.get("EXCHANGE_PASSWORD", "")
# Schutz gegen versehentliches Volllaufen der Platte durch einen einzelnen
# Upload - kein Limit fuer die Ablage insgesamt, nur pro Datei.
MAX_UPLOAD_BYTES = int(os.environ.get("EXCHANGE_MAX_UPLOAD_MB", "500")) * 1024 * 1024

os.makedirs(EXCHANGE_DIR, exist_ok=True)

# Dateinamen: kein Pfadtrennzeichen, kein führender Punkt (keine Ausbrueche,
# keine versteckten Dateien ueber die API) - dieselbe Grundidee wie
# android-mcp/server.py's _NAME_RE, nur fuer beliebige Dateinamen statt
# Projektnamen (Punkte im Dateinamen selbst sind erlaubt, z. B. "app.apk").
_UNSAFE_CHARS = re.compile(r"[\\/\x00]")


def _safe_name(name):
    """Dateinamen sichern: kein Pfadtrennzeichen, kein Ausbruch aus dem
    Ablageordner, kein führender Punkt. Gibt None zurück, wenn der Name
    nicht taugt."""
    name = urllib.parse.unquote(name or "").strip()
    if not name or name in (".", "..") or name.startswith("."):
        return None
    if _UNSAFE_CHARS.search(name):
        return None
    path = os.path.realpath(os.path.join(EXCHANGE_DIR, name))
    if os.path.commonpath([path, os.path.realpath(EXCHANGE_DIR)]) != os.path.realpath(EXCHANGE_DIR):
        return None
    return name


def _human_size(num_bytes):
    for unit in ("B", "KB", "MB", "GB"):
        if num_bytes < 1024 or unit == "GB":
            return f"{num_bytes:.0f} {unit}" if unit == "B" else f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:.1f} GB"


def list_files():
    entries = []
    for name in sorted(os.listdir(EXCHANGE_DIR)):
        if name.startswith("."):
            continue
        path = os.path.join(EXCHANGE_DIR, name)
        if not os.path.isfile(path):
            continue
        st = os.stat(path)
        entries.append({
            "name": name,
            "size": st.st_size,
            "size_human": _human_size(st.st_size),
            "modified": datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone.utc).isoformat(),
        })
    return entries


def _parse_multipart(body, boundary):
    """Sehr einfacher multipart/form-data-Parser für genau einen
    Datei-Teil ("file"). Kein cgi-Modul (in neueren Python-Versionen
    entfernt) - für den einen Anwendungsfall hier reicht das per Hand.
    Gibt (dateiname, inhalt) zurück oder (None, None)."""
    marker = b"--" + boundary.encode()
    parts = body.split(marker)
    for part in parts:
        # NICHT part.strip(b"\r\n") - das entfernt beliebig viele \r/\n
        # von beiden Raendern und frisst damit einen echten, zum Dateiinhalt
        # gehoerenden Zeilenumbruch mit, wenn die Datei selbst mit LF endet.
        # Nur die exakt zwei Rahmungs-Bytes nach der Boundary abschneiden.
        if part.startswith(b"\r\n"):
            part = part[2:]
        if not part or part == b"--" or part.startswith(b"--"):
            continue
        if b"\r\n\r\n" not in part:
            continue
        headers_raw, content = part.split(b"\r\n\r\n", 1)
        headers = headers_raw.decode("utf-8", errors="replace")
        if "filename=" not in headers:
            continue
        m = re.search(r'filename="([^"]*)"', headers)
        filename = m.group(1) if m else ""
        # Trailing "--\r\n" des letzten Teils sowie ein einzelnes
        # trailendes CRLF vor der naechsten Boundary entfernen.
        if content.endswith(b"\r\n"):
            content = content[:-2]
        return os.path.basename(filename), content
    return None, None


class Handler(BaseHTTPRequestHandler):
    server_version = "AIStackExchangeBridge/1.0"

    # ── Basic Auth ───────────────────────────────────────────────────────
    def _authorized(self):
        if not AUTH_PASSWORD:
            # Kein Passwort erzeugt (sollte durch install.sh nicht vorkommen)
            # -> sicherheitshalber ALLES sperren statt offen zu lassen.
            return False
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        import base64
        try:
            decoded = base64.b64decode(header[6:]).decode("utf-8")
            user, _, pw = decoded.partition(":")
        except Exception:  # noqa: BLE001
            return False
        return secrets.compare_digest(user, AUTH_USER) and secrets.compare_digest(pw, AUTH_PASSWORD)

    def _require_auth(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="Austausch-Ablage"')
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ── Hilfen ───────────────────────────────────────────────────────────
    def _send(self, code, body, ctype, extra_headers=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj), "application/json")

    # ── Routen ───────────────────────────────────────────────────────────
    def do_GET(self):  # noqa: N802 - vorgegebene Signatur
        if self.path == "/healthz":
            self._send(200, "ok", "text/plain")
            return

        if not self._authorized():
            self._require_auth()
            return

        if self.path == "/" or self.path == "":
            try:
                with open(os.path.join(HERE, "index.html"), "rb") as fh:
                    self._send(200, fh.read(), "text/html; charset=utf-8")
            except OSError:
                self._send(404, "not found", "text/plain")
            return

        if self.path == "/api/list":
            self._json(200, {"files": list_files(), "dir": EXCHANGE_DIR})
            return

        if self.path.startswith("/api/download/"):
            raw_name = self.path[len("/api/download/"):]
            name = _safe_name(raw_name)
            if not name:
                self._json(400, {"error": "Ungültiger Dateiname."})
                return
            path = os.path.join(EXCHANGE_DIR, name)
            if not os.path.isfile(path):
                self._json(404, {"error": "Datei nicht gefunden."})
                return
            with open(path, "rb") as fh:
                data = fh.read()
            quoted = urllib.parse.quote(name)
            self._send(
                200, data, "application/octet-stream",
                {"Content-Disposition": f"attachment; filename*=UTF-8''{quoted}"},
            )
            return

        self._json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802 - vorgegebene Signatur
        if not self._authorized():
            self._require_auth()
            return

        if self.path == "/api/upload":
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0:
                self._json(400, {"error": "Leere Anfrage."})
                return
            if length > MAX_UPLOAD_BYTES:
                # Erst lesen wuerde unnoetig Speicher/Zeit verschwenden -
                # Content-Length steht vorher schon fest.
                self._json(413, {"error": f"Datei zu groß (Limit {MAX_UPLOAD_BYTES // (1024*1024)} MB)."})
                return
            content_type = self.headers.get("Content-Type", "")
            m = re.search(r"boundary=(.+)", content_type)
            if not m:
                self._json(400, {"error": "Kein multipart/form-data (fehlende Boundary)."})
                return
            boundary = m.group(1).strip().strip('"')
            body = self.rfile.read(length)
            filename, content = _parse_multipart(body, boundary)
            if not filename or content is None:
                self._json(400, {"error": "Keine Datei im Formular gefunden."})
                return
            name = _safe_name(filename)
            if not name:
                self._json(400, {"error": "Ungültiger Dateiname."})
                return
            with open(os.path.join(EXCHANGE_DIR, name), "wb") as fh:
                fh.write(content)
            self._json(200, {"ok": True, "name": name, "size": len(content)})
            return

        self._json(404, {"error": "not found"})

    def do_DELETE(self):  # noqa: N802 - vorgegebene Signatur
        if not self._authorized():
            self._require_auth()
            return

        if self.path.startswith("/api/file/"):
            raw_name = self.path[len("/api/file/"):]
            name = _safe_name(raw_name)
            if not name:
                self._json(400, {"error": "Ungültiger Dateiname."})
                return
            path = os.path.join(EXCHANGE_DIR, name)
            if not os.path.isfile(path):
                self._json(404, {"error": "Datei nicht gefunden."})
                return
            os.remove(path)
            self._json(200, {"ok": True})
            return

        self._json(404, {"error": "not found"})

    def log_message(self, *args):  # Logs ruhig halten
        return


def main():
    if not AUTH_PASSWORD:
        print("WARNUNG: EXCHANGE_PASSWORD nicht gesetzt - die Ablage bleibt für alle Anfragen gesperrt.")
    httpd = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"Austausch-Ablage läuft auf Port {LISTEN_PORT} (Ordner: {EXCHANGE_DIR})")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
