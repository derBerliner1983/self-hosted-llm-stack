#!/usr/bin/env python3
"""
MCP-Zeit-Werkzeug für den Self-Hosted AI Stack.

Liefert die exakte aktuelle Uhrzeit für beliebige IANA-Zeitzonen (z. B.
"Asia/Bangkok", "Europe/Berlin", "America/Vancouver") — berechnet mit
Pythons Standardbibliothek `zoneinfo`, die Sommer-/Winterzeit korrekt
kennt. Nicht vom Sprachmodell selbst ausgerechnet: Im Live-Betrieb hat
sich gezeigt, dass Modelle bei Zeitzonen-Kopfrechnung regelmäßig falsch
liegen (Sommerzeit vergessen, Rechenfehler) — dieses Werkzeug macht die
Rechnung stattdessen mit echtem, deterministischem Code.

Protokoll: MCP über stdio (newline-getrennte JSON-RPC-Nachrichten), siehe
https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
Bewusst ohne das offizielle `mcp`-Python-SDK geschrieben (im mcp-Gateway-
Image nicht vorinstalliert) — nur Standardbibliothek, kein `pip install`
oder `uvx`-Download beim ersten Aufruf nötig.

Eingebunden wird das Werkzeug über /var/lib/mcp/mcp_settings.json:
  "time": {"command": "python3", "args": ["/opt/mcp-tools/get_time.py"]}
(siehe README, Abschnitt "Zeit-Werkzeug" bzw. scripts/wire-mcp.sh)

This file is part of Self-Hosted AI Stack.
Licensed under the MIT License: https://opensource.org/licenses/MIT
"""

import json
import sys
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

PROTOCOL_VERSION = "2025-06-18"
SERVER_NAME = "self-hosted-ai-stack-time"
SERVER_VERSION = "1.0.0"

TOOL_NAME = "get_time"
TOOL = {
    "name": TOOL_NAME,
    "description": (
        "Get the current, exact date and time for one or more IANA timezones "
        "(e.g. 'Asia/Bangkok', 'Europe/Berlin', 'America/Vancouver'). "
        "Correctly accounts for daylight saving time. Use this instead of "
        "calculating time zone offsets yourself - manual arithmetic is "
        "unreliable and often wrong, especially around DST transitions. "
        "Pass multiple timezones at once instead of calling this repeatedly."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "timezones": {
                "type": "array",
                "items": {"type": "string"},
                "description": (
                    "One or more IANA timezone names, e.g. "
                    "['Asia/Bangkok', 'America/Vancouver', 'Europe/Berlin']."
                ),
            }
        },
        "required": ["timezones"],
    },
}


def _send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _result(msg_id, result):
    _send({"jsonrpc": "2.0", "id": msg_id, "result": result})


def _error(msg_id, code, message):
    _send({"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}})


def _format_zone(tz_name):
    if not isinstance(tz_name, str) or not tz_name.strip():
        return f"(leer): kein gültiger Zeitzonen-Name."
    try:
        now = datetime.now(ZoneInfo(tz_name))
    except (ZoneInfoNotFoundError, KeyError, ValueError) as exc:
        return f"{tz_name}: Ungültige Zeitzone ({exc}). Format: IANA-Name wie 'Asia/Bangkok'."
    offset = now.utcoffset()
    total_minutes = int(offset.total_seconds() // 60) if offset else 0
    sign = "+" if total_minutes >= 0 else "-"
    hh, mm = divmod(abs(total_minutes), 60)
    offset_str = f"UTC{sign}{hh:02d}:{mm:02d}"
    dst_active = bool(now.dst() and now.dst().total_seconds() != 0)
    weekday = now.strftime("%A")
    return (
        f"{tz_name}: {now.strftime('%Y-%m-%d %H:%M:%S')} {weekday} "
        f"({offset_str}, Sommerzeit aktiv: {'ja' if dst_active else 'nein'})"
    )


def handle_tools_call(params):
    name = params.get("name")
    if name != TOOL_NAME:
        return {
            "content": [{"type": "text", "text": f"Unbekanntes Werkzeug: {name}"}],
            "isError": True,
        }
    args = params.get("arguments") or {}
    timezones = args.get("timezones")
    if isinstance(timezones, str):
        timezones = [timezones]
    if not timezones:
        return {
            "content": [{"type": "text", "text": "Parameter 'timezones' fehlt oder ist leer."}],
            "isError": True,
        }
    lines = [_format_zone(tz) for tz in timezones]
    return {"content": [{"type": "text", "text": "\n".join(lines)}], "isError": False}


def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue  # kein gültiges MCP-Message - laut Spec ignorieren, nicht abstürzen

        method = msg.get("method")
        msg_id = msg.get("id")
        has_id = "id" in msg  # unterscheidet Request (Antwort erwartet) von Notification

        if method == "initialize":
            _result(msg_id, {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            })
        elif method == "notifications/initialized":
            pass  # keine Antwort - ist eine Notification
        elif method == "tools/list":
            _result(msg_id, {"tools": [TOOL]})
        elif method == "tools/call":
            try:
                result = handle_tools_call(msg.get("params") or {})
            except Exception as exc:  # noqa: BLE001 - Prozess läuft immer weiter
                result = {
                    "content": [{"type": "text", "text": f"Interner Fehler: {exc}"}],
                    "isError": True,
                }
            if has_id:
                _result(msg_id, result)
        elif method == "ping":
            if has_id:
                _result(msg_id, {})
        else:
            if has_id:
                _error(msg_id, -32601, f"Method not found: {method}")
            # unbekannte Notifications werden laut Spec einfach ignoriert


if __name__ == "__main__":
    main()
