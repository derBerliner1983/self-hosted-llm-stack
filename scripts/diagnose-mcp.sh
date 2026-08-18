#!/usr/bin/env bash
#
# Prüft, warum LibreChat (oder Open WebUI) keine MCP-Werkzeuge sieht.
#
# Geht die Kette von hinten durch: laufen die MCP-Dienste, antworten sie auf
# das MCP-Protokoll, kommt LibreChat aus SEINEM Container dort an, und stimmt
# der Schlüssel? Jeder Schritt sagt, was zu tun ist, wenn er fehlschlägt.
#
# Aufruf: ./scripts/diagnose-mcp.sh
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'
step() { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_reset"; }
ok()   { printf '  %s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yellow" "$c_reset" "$1"; PROBLEMS=$((PROBLEMS+1)); }
fail() { printf '  %s✗%s %s\n' "$c_red" "$c_reset" "$1"; PROBLEMS=$((PROBLEMS+1)); }
hint() { printf '    %s%s%s\n' "$c_dim" "$1" "$c_reset"; }

PROBLEMS=0
cd "$ROOT_DIR" || exit 1
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

printf '%s' "$c_bold"
cat <<'BANNER'
╔══════════════════════════════════════════════════════╗
║   MCP-Werkzeuge · Fehlersuche                        ║
╚══════════════════════════════════════════════════════╝
BANNER
printf '%s' "$c_reset"

# ── 1) Laufen die Dienste? ──────────────────────────────────────────────────
step "1/5 · Laufen die MCP-Dienste?"
RUNNING=" $(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
for c in mcp sandbox-mcp android-mcp librechat; do
  case "$RUNNING" in
    *" $c "*) ok "$c läuft" ;;
    *) if [ "$c" = "android-mcp" ]; then
         warn "$c läuft nicht (nur nötig, wenn du Android-Werkzeuge nutzt)"
       else
         fail "$c läuft nicht"
         hint "Starten: docker compose -f $COMPOSE_FILE up -d $c"
       fi ;;
  esac
done

# ── 2) Schlüssel vorhanden? ─────────────────────────────────────────────────
step "2/5 · MCP-Schlüssel"
if [ -z "${MCP_API_KEY:-}" ]; then
  fail "MCP_API_KEY fehlt in der .env"
  hint "Das MCP Gateway lehnt Anfragen ohne gültigen Schlüssel ab —"
  hint "LibreChat meldet dann 'MCP tools unavailable'."
  hint "Erzeugen und eintragen: ./scripts/wire-mcp.sh"
else
  ok "MCP_API_KEY steht in der .env"
  # Entscheidend ist nicht die .env, sondern was IM Container ankommt:
  # Compose reicht Variablen nur beim (Neu-)Erzeugen des Containers durch.
  IN_LC="$(docker exec librechat printenv MCP_API_KEY 2>/dev/null)"
  if [ -z "$IN_LC" ]; then
    fail "Im librechat-Container ist MCP_API_KEY LEER"
    hint "Der Container wurde vor dem Eintragen des Schlüssels erzeugt."
    hint "Beheben: docker compose -f $COMPOSE_FILE up -d --force-recreate librechat"
  elif [ "$IN_LC" != "$MCP_API_KEY" ]; then
    fail "Im Container steht ein ANDERER Schlüssel als in der .env"
    hint "Beheben: docker compose -f $COMPOSE_FILE up -d --force-recreate librechat"
  else
    ok "Derselbe Schlüssel ist im librechat-Container angekommen"
  fi
fi

# ── 3) Antworten die Dienste auf MCP? ───────────────────────────────────────
# Eine echte initialize-Anfrage — nur so zeigt sich, ob dort wirklich ein
# MCP-Server sitzt und den Schlüssel akzeptiert. Ein offener Port sagt nichts.
step "3/5 · Sprechen die Dienste MCP?"
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"diagnose","version":"1.0"}}}'

probe() {
  local name="$1" url="$2" auth="$3" body code
  body="$(docker exec librechat curl -s -o /tmp/mcp-probe.out -w '%{http_code}' --max-time 12 \
    -X POST "$url" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    ${auth:+-H "Authorization: Bearer $auth"} \
    -d "$INIT" 2>/dev/null)"
  code="$body"
  case "$code" in
    200)
      if docker exec librechat sh -c 'grep -q "serverInfo\|protocolVersion" /tmp/mcp-probe.out' 2>/dev/null; then
        ok "$name antwortet als MCP-Server"
      else
        warn "$name antwortet mit 200, aber ohne MCP-Inhalt"
        docker exec librechat sh -c 'head -c 200 /tmp/mcp-probe.out' 2>/dev/null | sed 's/^/      /'; echo
      fi ;;
    401|403)
      fail "$name lehnt den Schlüssel ab (HTTP $code)"
      hint "Schlüssel neu verdrahten: ./scripts/wire-mcp.sh"
      hint "danach: docker compose -f $COMPOSE_FILE up -d --force-recreate librechat" ;;
    404)
      fail "$name: Pfad nicht gefunden (HTTP 404) — falsche URL in librechat.yaml?" ;;
    000|"")
      fail "$name ist aus dem librechat-Container nicht erreichbar"
      hint "Hängen beide im selben Docker-Netz? docker network inspect \$(docker inspect -f '{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}}{{end}}' librechat)" ;;
    *)
      fail "$name antwortet mit HTTP $code"
      docker exec librechat sh -c 'head -c 200 /tmp/mcp-probe.out' 2>/dev/null | sed 's/^/      /'; echo ;;
  esac
}

case "$RUNNING" in
  *" librechat "*)
    probe "mcp_gateway"  "http://mcp:3000/mcp"          "${MCP_API_KEY:-}"
    probe "code_sandbox" "http://sandbox-mcp:8000/mcp"  ""
    case "$RUNNING" in *" android-mcp "*) probe "android_build" "http://android-mcp:8000/mcp" "" ;; esac ;;
  *) fail "Ohne laufenden librechat-Container nicht prüfbar" ;;
esac

# ── 4) Was sagt LibreChat beim Start? ───────────────────────────────────────
step "4/5 · Meldungen von LibreChat"
LOG="$(docker logs librechat 2>&1 | grep -iE 'mcp' | tail -15)"
if [ -z "$LOG" ]; then
  warn "Keine MCP-Meldungen im Log — wird die librechat.yaml überhaupt gelesen?"
  hint "Prüfen: docker exec librechat sh -c 'head -5 /app/librechat.yaml'"
  hint "CONFIG_PATH muss auf /app/librechat.yaml zeigen."
else
  printf '%s\n' "$LOG" | sed 's/^/    /'
  if printf '%s' "$LOG" | grep -qiE 'error|failed|unavailable|refused'; then
    fail "Das Log meldet Fehler (siehe oben)"
  else
    ok "Keine Fehler in den MCP-Meldungen"
  fi
fi

# ── 5) Konfiguration im Container ───────────────────────────────────────────
step "5/5 · Konfiguration im Container"
if docker exec librechat sh -c 'grep -q "^mcpServers:" /app/librechat.yaml' 2>/dev/null; then
  ok "mcpServers steht in der Konfiguration"
  docker exec librechat sh -c "sed -n '/^mcpServers:/,\$p' /app/librechat.yaml | grep -E '^  [a-z_]+:|url:'" 2>/dev/null | sed 's/^/    /'
else
  fail "In /app/librechat.yaml steht kein mcpServers-Block"
  hint "Ist librechat/librechat.yaml eingehängt? docker compose -f $COMPOSE_FILE up -d --force-recreate librechat"
fi

# ── Fazit ───────────────────────────────────────────────────────────────────
step "Fazit"
if [ "$PROBLEMS" -eq 0 ]; then
  ok "Technisch ist alles in Ordnung."
  printf '\n  %sBleibt die Meldung "AGENT_EXPECTED_MCP_TOOLS_UNAVAILABLE", liegt es am\n' "$c_dim"
  printf '  Agenten selbst: In LibreChat unter Agenten -> Bearbeiten -> Werkzeuge\n'
  printf '  müssen die MCP-Werkzeuge ausgewählt sein. Ein Agent mit abgewählten\n'
  printf '  oder umbenannten Werkzeugen meldet genau diesen Fehler.%s\n' "$c_reset"
else
  printf '  %s%d Punkt(e) zu klären — siehe oben.%s\n' "$c_yellow" "$PROBLEMS" "$c_reset"
fi
printf '\n  %sHäufigste Ursache:%s LibreChat verbindet die MCP-Server beim START.\n' "$c_bold" "$c_reset"
printf '  Lief ein Dienst damals noch nicht (oder wurde er seither neu erzeugt),\n'
printf '  bleibt er für LibreChat verschwunden, bis LibreChat selbst neu startet:\n\n'
printf '    docker compose -f %s restart librechat\n' "$COMPOSE_FILE"
printf '\n  %sDasselbe gilt nach jeder Änderung an librechat.yaml.%s\n' "$c_dim" "$c_reset"
