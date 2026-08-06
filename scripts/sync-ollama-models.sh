#!/usr/bin/env bash
#
# Trägt alle in Ollama geladenen Modelle automatisch bei LiteLLM ein.
#
# Angepasst an den ROCm-Stack (Upstream-Images): vanilla-Ollama und
# vanilla-LiteLLM haben keine *_manage-Tools. Wir lesen daher:
#   - die Modelliste über die Ollama-API (/api/tags)
#   - den LiteLLM-Master-Key aus der .env
# und registrieren nur Modelle, die bei LiteLLM noch fehlen (idempotent).
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

info()  { printf '\033[0;34m•\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m!\033[0m %s\n' "$*"; }

# Ollama-Modelle über die API (im Container ausgeführt, daher localhost:11434).
info "Frage geladene Ollama-Modelle ab…"
ALL_MODELS="$(docker exec ollama sh -c \
  'curl -s http://localhost:11434/api/tags' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); [print(m['name']) for m in d.get('models',[])]" 2>/dev/null || true)"

if [ -z "${ALL_MODELS// }" ]; then
  warn "Keine Ollama-Modelle gefunden. Erst ein Modell laden: docker exec ollama ollama pull <modell>"
  exit 0
fi

# Bereits bei LiteLLM registrierte Modelle (nur ollama/-Präfix).
EXISTING="$(curl -s "${LITELLM_URL}/v1/models" -H "Authorization: Bearer ${LITELLM_KEY}" \
  | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    for m in d.get('data',[]):
        i=m.get('id','')
        if i.startswith('ollama/'): print(i.replace('ollama/',''))
except Exception:
    pass" 2>/dev/null || true)"

echo "Gefundene Ollama-Modelle:"
echo "$ALL_MODELS" | sed 's/^/  - /'
echo "Bereits bei LiteLLM (ollama/):"
if [ -n "${EXISTING// }" ]; then echo "$EXISTING" | sed 's/^/  - /'; else echo "  (keine)"; fi
echo "---"

for MODEL in $ALL_MODELS; do
  if echo "$EXISTING" | grep -qx "$MODEL"; then
    info "Übersprungen (schon vorhanden): ollama/${MODEL}"
    continue
  fi

  info "Trage neu ein: ollama/${MODEL}"
  curl -s -X POST "${LITELLM_URL}/model/new" \
    -H "Authorization: Bearer ${LITELLM_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"model_name\": \"ollama/${MODEL}\",
      \"litellm_params\": {
        \"model\": \"ollama/${MODEL}\",
        \"api_base\": \"${OLLAMA_API_BASE}\"
      }
    }" >/dev/null && ok "ollama/${MODEL} eingetragen" || warn "Fehler bei ollama/${MODEL}"
done

echo "---"
ok "Fertig. Aktuelle Modelle bei LiteLLM:"
curl -s "${LITELLM_URL}/v1/models" -H "Authorization: Bearer ${LITELLM_KEY}" \
  | python3 -m json.tool 2>/dev/null || true
