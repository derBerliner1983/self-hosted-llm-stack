#!/usr/bin/env bash
#
# Trägt alle in Ollama geladenen Modelle automatisch bei LiteLLM ein.
#
# Curl-frei: die Modelliste kommt aus 'ollama list' (im Container), die
# LiteLLM-Aufrufe laufen über python3 (auf dem Host vorhanden). So werden
# weder im schlanken ollama-Image noch auf dem Host zusätzliche Tools
# gebraucht. Idempotent: bereits korrekt eingetragene Modelle werden
# übersprungen.
#
# Selbstheilend: frühere Läufe dieses Skripts haben Modelle über LiteLLMs
# eigenen "ollama"-Provider eingetragen (litellm_params.model = "ollama/…").
# Der übersetzt Werkzeugaufrufe (tool_calls) nicht zuverlässig - Ollama
# selbst liefert sie korrekt strukturiert (geprüft direkt gegen Ollama,
# sowohl über /api/chat als auch /v1/chat/completions), aber bei LiteLLMs
# "ollama/"-Route kommt beim Client nur noch roher JSON-Text an statt eines
# echten Funktionsaufrufs. Ein Eintrag mit diesem alten Format wird darum
# bei jedem Lauf erkannt, gelöscht und mit dem "openai/"-Provider (gegen
# Ollamas OpenAI-kompatiblen Endpunkt, .../v1) neu angelegt - siehe
# litellm/config.yaml für dieselbe Umstellung bei den fest eingetragenen
# Modellen.
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# .env laden (für LITELLM_MASTER_KEY und Ports)
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi

LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-1234}"
PORT_LITELLM="${PORT_LITELLM:-4000}"
LITELLM_URL="http://localhost:${PORT_LITELLM}"
# api_base, unter dem LiteLLM den Ollama-Container erreicht (im Docker-Netz).
# Der OpenAI-kompatible Endpunkt liegt unter "/v1" - siehe Kommentar oben.
OLLAMA_API_BASE="http://ollama:11434/v1"
# Platzhalter: Ollamas /v1-Endpunkt prüft den Schlüssel nicht, LiteLLMs
# "openai"-Provider verlangt aber irgendeinen nicht-leeren Wert.
OLLAMA_API_KEY="ollama"

command -v python3 >/dev/null 2>&1 || { echo "python3 wird benötigt (bitte installieren)."; exit 1; }

echo "• Frage geladene Ollama-Modelle ab…"
# 'ollama list'-Tabelle -> nur echte Modellzeilen (Spalte 1 enthält 'name:tag')
ALL_MODELS="$(docker exec ollama ollama list 2>/dev/null | awk 'NR>1 && $1 ~ /:/ {print $1}')"

if [ -z "${ALL_MODELS// }" ]; then
  echo "! Keine Ollama-Modelle gefunden. Erst eins laden, z. B.:"
  echo "    docker exec ollama ollama pull ${DEFAULT_MODEL:-gemma3:12b}"
  exit 0
fi

echo "Gefundene Ollama-Modelle:"
echo "$ALL_MODELS" | sed 's/^/  - /'
echo "---"

export LITELLM_URL LITELLM_KEY OLLAMA_API_BASE OLLAMA_API_KEY ALL_MODELS
python3 <<'PY'
import os, json, urllib.request, urllib.error

base = os.environ["LITELLM_URL"].rstrip("/")
key  = os.environ["LITELLM_KEY"]
obase = os.environ["OLLAMA_API_BASE"]
okey = os.environ["OLLAMA_API_KEY"]
models = [m.strip() for m in os.environ["ALL_MODELS"].splitlines() if m.strip()]

def api(path, method="GET", payload=None):
    req = urllib.request.Request(
        base + path, method=method,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    if payload is not None:
        req.data = json.dumps(payload).encode()
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}

def register(name):
    api("/model/new", "POST", {
        "model_name": "ollama/%s" % name,
        "litellm_params": {"model": "openai/%s" % name, "api_base": obase, "api_key": okey},
    })

# Volle Eintraege lesen (nicht nur /v1/models): litellm_params.model verrät,
# ob ein vorhandener Eintrag noch den alten, kaputten "ollama/"-Provider
# benutzt und repariert werden muss. model_info.id + db_model sagen, ob
# sich der Eintrag ueberhaupt loeschen laesst (nur datenbankgestuetzte
# Eintraege - die drei fest in litellm/config.yaml eingetragenen Modelle
# sind das nicht und werden hier nicht angefasst).
existing = {}
try:
    data = api("/model/info")
    for entry in data.get("data", []):
        mn = entry.get("model_name", "")
        if not mn.startswith("ollama/"):
            continue
        info = entry.get("model_info", {}) or {}
        existing[mn[len("ollama/"):]] = {
            "id": info.get("id"),
            "db_model": info.get("db_model", False),
            "provider_model": (entry.get("litellm_params", {}) or {}).get("model", ""),
        }
except Exception as e:  # noqa: BLE001
    print("! Konnte LiteLLM-Modelle nicht lesen (läuft LiteLLM schon?):", e)

added = 0
repaired = 0
for name in models:
    cur = existing.get(name)
    if cur is None:
        try:
            register(name)
            print("\033[0;32m✓\033[0m Eingetragen: ollama/%s" % name)
            added += 1
        except Exception as e:  # noqa: BLE001
            print("! Fehler bei ollama/%s: %s" % (name, e))
        continue

    if cur["provider_model"].startswith("openai/"):
        print("• Übersprungen (schon korrekt): ollama/%s" % name)
        continue

    if not cur["db_model"] or not cur["id"]:
        # Ein fest in litellm/config.yaml eingetragenes Modell mit altem
        # Format - das aendert die Konfigurationsdatei, nicht die API.
        print("! ollama/%s: alter Provider, aber nicht über die API änderbar "
              "(steht fest in litellm/config.yaml - dort geändert, Neustart "
              "von litellm nötig)." % name)
        continue

    try:
        api("/model/delete", "POST", {"id": cur["id"]})
        register(name)
        print("\033[0;33m↻\033[0m Repariert (alter Provider ersetzt): ollama/%s" % name)
        repaired += 1
    except Exception as e:  # noqa: BLE001
        print("! Fehler beim Reparieren von ollama/%s: %s" % (name, e))

print("---")
print("Fertig. Neu eingetragen: %d, repariert: %d" % (added, repaired))
try:
    data = api("/v1/models")
    ids = [m.get("id") for m in data.get("data", []) if m.get("id", "").startswith("ollama/")]
    print("Aktuell bei LiteLLM:", ", ".join(sorted(ids)) or "(keine)")
except Exception:
    pass
PY
