#!/usr/bin/env bash
#
# Diagnose für "komische" Chat-Antworten (z. B. Open WebUI zeigt nur
# { "title": "..." } statt einer echten Antwort auf "hallo").
#
# Testet die Kette Schicht für Schicht, damit klar wird, WO das Problem
# liegt — nicht nur DASS eines existiert:
#
#   1) Ollama direkt          (Modell + Chat-Template korrekt?)
#   2) LiteLLM direkt         (Routing/Verdrahtung zu Ollama korrekt?)
#   3) Hinweise zu Open WebUI (Titel-/Tag-Generierung als häufige Ursache)
#
# Curl-frei (wie sync-ollama-models.sh): läuft über python3 auf dem Host,
# damit es unabhängig davon funktioniert, ob curl installiert ist.
#
# Aufruf:
#   ./scripts/diagnose-chat.sh                       # nutzt DEFAULT_MODEL aus .env
#   ./scripts/diagnose-chat.sh qwen3-coder-next:latest
#   ./scripts/diagnose-chat.sh qwen3-coder-next:latest "wie spät ist es?"
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'

step()  { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_reset"; }
ok()    { printf '  %s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
warn()  { printf '  %s!%s %s\n' "$c_yellow" "$c_reset" "$1"; }
fail()  { printf '  %s✗%s %s\n' "$c_red" "$c_reset" "$1"; }

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
else
  warn "Keine .env gefunden unter $ENV_FILE — nutze Standardwerte."
fi

LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-1234}"
PORT_LITELLM="${PORT_LITELLM:-4000}"
PORT_OLLAMA="${PORT_OLLAMA:-11434}"
MODEL="${1:-${DEFAULT_MODEL:-}}"
MESSAGE="${2:-hallo}"

if [ -z "$MODEL" ]; then
  fail "Kein Modell angegeben und DEFAULT_MODEL nicht in .env gesetzt."
  echo "  Aufruf: ./scripts/diagnose-chat.sh <modellname> [nachricht]"
  echo "  Installierte Modelle: docker exec ollama ollama list"
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { fail "python3 wird benötigt."; exit 1; }
command -v docker  >/dev/null 2>&1 || { fail "docker wird benötigt."; exit 1; }

printf '%sDiagnose: Modell=%s%s  Nachricht=%s%s%s\n' "$c_bold" "$c_reset" "$MODEL" "$c_dim" "$MESSAGE" "$c_reset"

# ── 1) Chat-Template des Modells prüfen ─────────────────────────────────────
step "1/3 · Ollama-Modelfile (Chat-Template)"
MODELFILE="$(docker exec ollama ollama show "$MODEL" --modelfile 2>&1)" || {
  fail "Konnte Modelfile nicht lesen — ist '$MODEL' installiert? (docker exec ollama ollama list)"
  exit 1
}
if echo "$MODELFILE" | grep -q '^TEMPLATE'; then
  ok "Modell hat ein eigenes TEMPLATE (Chat-Format vom Ersteller vorgegeben)."
else
  warn "Kein eigenes TEMPLATE im Modelfile gefunden — Ollama nutzt ein generisches Fallback-Template."
  warn "Das ist eine häufige Ursache für kaputte/JSON-artige Antworten bei Modellen,"
  warn "die per 'hf.co/...'-Referenz geladen wurden und kein GGUF-eingebettetes"
  warn "Chat-Template mitbringen (z. B. weil es beim Quantisieren verloren ging)."
fi

# ── 2) Ollama direkt ansprechen (ohne LiteLLM) ──────────────────────────────
step "2/3 · Ollama direkt (http://localhost:${PORT_OLLAMA}/api/chat)"
OLLAMA_OUT="$(python3 - "$PORT_OLLAMA" "$MODEL" "$MESSAGE" <<'PY'
import json, sys, urllib.request

port, model, message = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": message}],
    "stream": False,
}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/api/chat", data=payload,
    headers={"Content-Type": "application/json"}, method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read())
    content = body.get("message", {}).get("content", "")
    print("OK")
    print(content)
except Exception as exc:  # noqa: BLE001
    print("ERROR")
    print(str(exc))
PY
)"
OLLAMA_STATUS="$(echo "$OLLAMA_OUT" | head -1)"
OLLAMA_CONTENT="$(echo "$OLLAMA_OUT" | tail -n +2)"

if [ "$OLLAMA_STATUS" = "OK" ]; then
  printf '  Antwort: %s"%s"%s\n' "$c_dim" "$(echo "$OLLAMA_CONTENT" | head -c 300)" "$c_reset"
  if echo "$OLLAMA_CONTENT" | grep -qE '^\s*\{.*"title"'; then
    fail "Ollama selbst liefert schon die kaputte {\"title\": ...}-Antwort."
    fail "-> Problem liegt am Modell/Chat-Template, NICHT an der WebUI/LiteLLM-Verdrahtung."
  else
    ok "Ollama antwortet direkt sauber."
  fi
else
  fail "Ollama-Aufruf fehlgeschlagen: $OLLAMA_CONTENT"
fi

# ── 3) LiteLLM ansprechen (wie Open WebUI es tut) ───────────────────────────
step "3/3 · LiteLLM (http://localhost:${PORT_LITELLM}/v1/chat/completions)"
LITELLM_OUT="$(python3 - "$PORT_LITELLM" "$LITELLM_KEY" "$MODEL" "$MESSAGE" <<'PY'
import json, sys, urllib.request, urllib.error

port, key, model, message = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
payload = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": message}],
    "stream": False,
}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/chat/completions", data=payload,
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read())
    content = body["choices"][0]["message"].get("content", "")
    print("OK")
    print(content)
except urllib.error.HTTPError as exc:
    print("ERROR")
    print(f"HTTP {exc.code}: {exc.read().decode(errors='replace')[:500]}")
except Exception as exc:  # noqa: BLE001
    print("ERROR")
    print(str(exc))
PY
)"
LITELLM_STATUS="$(echo "$LITELLM_OUT" | head -1)"
LITELLM_CONTENT="$(echo "$LITELLM_OUT" | tail -n +2)"

if [ "$LITELLM_STATUS" = "OK" ]; then
  printf '  Antwort: %s"%s"%s\n' "$c_dim" "$(echo "$LITELLM_CONTENT" | head -c 300)" "$c_reset"
  if echo "$LITELLM_CONTENT" | grep -qE '^\s*\{.*"title"'; then
    if [ "$OLLAMA_STATUS" = "OK" ] && ! echo "$OLLAMA_CONTENT" | grep -qE '^\s*\{.*"title"'; then
      fail "LiteLLM liefert die kaputte {\"title\": ...}-Antwort, Ollama direkt aber NICHT."
      fail "-> Problem liegt an der LiteLLM-Verdrahtung/Konfiguration, nicht am Modell selbst."
    else
      fail "Auch LiteLLM liefert die kaputte Antwort (wie schon Ollama direkt)."
    fi
  else
    ok "LiteLLM antwortet sauber — Verdrahtung LiteLLM<->Ollama ist in Ordnung."
  fi
else
  fail "LiteLLM-Aufruf fehlgeschlagen: $LITELLM_CONTENT"
fi

# ── Fazit ────────────────────────────────────────────────────────────────
step "Fazit"
if [ "$OLLAMA_STATUS" = "OK" ] && [ "$LITELLM_STATUS" = "OK" ] \
   && ! echo "$OLLAMA_CONTENT" | grep -qE '^\s*\{.*"title"' \
   && ! echo "$LITELLM_CONTENT" | grep -qE '^\s*\{.*"title"'; then
  ok "Ollama UND LiteLLM antworten hier beide sauber auf '$MESSAGE'."
  echo "  Das { \"title\": ... } in Open WebUI kommt in diesem Fall sehr wahrscheinlich"
  echo "  von Open WebUIs eigener Hintergrund-Funktion \"Titel automatisch generieren\","
  echo "  die nach jeder ersten Nachricht einen ZUSÄTZLICHEN, separaten Request an"
  echo "  dasselbe Modell schickt (Prompt: \"Antworte als JSON {\\\"title\\\": ...}\")."
  echo "  Bei manchen Modellen (v. a. große/eigene GGUF-Importe wie qwen3-coder-next)"
  echo "  wird diese interne Titel-Antwort fälschlich als Chat-Antwort angezeigt."
  echo
  echo "  Zu prüfen in Open WebUI:"
  echo "    Admin-Einstellungen -> Schnittstelle (Interface)"
  echo "      -> \"Titel automatisch generieren\" (Title Auto-Generation): ausschalten,"
  echo "         ODER dort ein anderes/kleineres, zuverlässiges Modell als"
  echo "         \"Aufgaben-Modell\" (Task Model) einstellen statt qwen3-coder-next."
  echo "      -> ebenso bei \"Tags generieren\" / \"Autovervollständigung\" prüfen,"
  echo "         falls die auch aktiv sind."
elif echo "$OLLAMA_CONTENT" | grep -qE '^\s*\{.*"title"'; then
  echo "  Modell/Chat-Template-Problem — kein WebUI/LiteLLM-Verdrahtungsfehler."
  echo "  Nächster Schritt: Modelfile des Modells ansehen und ggf. ein passendes"
  echo "  TEMPLATE ergänzen, oder ein anderes Quant/GGUF mit eingebettetem"
  echo "  Chat-Template dieses Modells laden:"
  echo "    docker exec ollama ollama show $MODEL --modelfile"
else
  echo "  Siehe die Fehler/Hinweise oben je Schicht."
fi
