#!/usr/bin/env bash
#
# Trägt alle in Ollama geladenen Modelle automatisch bei LiteLLM ein.
#
# Curl-frei: die Modelliste kommt aus 'ollama list' (im Container), die
# LiteLLM-Aufrufe laufen über python3 (auf dem Host vorhanden). So werden
# weder im schlanken ollama-Image noch auf dem Host zusätzliche Tools
# gebraucht. Idempotent: bereits eingetragene Modelle werden übersprungen.
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
OLLAMA_API_BASE="http://ollama:11434"

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

export LITELLM_URL LITELLM_KEY OLLAMA_API_BASE ALL_MODELS
python3 <<'PY'
import os, json, urllib.request, urllib.error

base = os.environ["LITELLM_URL"].rstrip("/")
key  = os.environ["LITELLM_KEY"]
obase = os.environ["OLLAMA_API_BASE"]
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

# Bereits registrierte ollama/-Modelle einsammeln
existing = set()
try:
    data = api("/v1/models")
    for m in data.get("data", []):
        i = m.get("id", "")
        if i.startswith("ollama/"):
            existing.add(i[len("ollama/"):])
except Exception as e:  # noqa: BLE001
    print("! Konnte LiteLLM-Modelle nicht lesen (läuft LiteLLM schon?):", e)

added = 0
for name in models:
    if name in existing:
        print("• Übersprungen (schon vorhanden): ollama/%s" % name)
        continue
    try:
        api("/model/new", "POST", {
            "model_name": "ollama/%s" % name,
            "litellm_params": {"model": "ollama/%s" % name, "api_base": obase},
        })
        print("\033[0;32m✓\033[0m Eingetragen: ollama/%s" % name)
        added += 1
    except Exception as e:  # noqa: BLE001
        print("! Fehler bei ollama/%s: %s" % (name, e))

print("---")
print("Fertig. Neu eingetragen: %d" % added)
try:
    data = api("/v1/models")
    ids = [m.get("id") for m in data.get("data", []) if m.get("id", "").startswith("ollama/")]
    print("Aktuell bei LiteLLM:", ", ".join(sorted(ids)) or "(keine)")
except Exception:
    pass
PY
