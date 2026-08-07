#!/usr/bin/env bash
#
# Verdrahtet MCP Gateway mit LiteLLM UND mit Open WebUI.
#
# Das vanilla-LiteLLM-Image (im Gegensatz zu hwdsl2/litellm-server) teilt
# API-Keys nicht automatisch über Volumes. Dieses Skript holt den vom
# mcp-Container erzeugten API-Key, schreibt ihn als MCP_API_KEY in die .env
# und startet LiteLLM neu, damit litellm/config.yaml (mcp_servers.*.auth_value
# = os.environ/MCP_API_KEY) ihn übernimmt.
#
# Open WebUI spricht kein rohes MCP, sondern nur OpenAPI — deshalb rendert
# dieses Skript zusätzlich mcpo/config.json (mit dem echten Key statt des
# Platzhalters __MCP_API_KEY__) und startet den mcpo-Dienst (MCP→OpenAPI-
# Proxy), den Open WebUI unter Admin-Einstellungen → Werkzeuge einbinden kann.
#
# Aufruf: ./scripts/wire-mcp.sh
# Erneut ausführen, falls der mcp-Container neu erzeugt wurde (neuer Key).
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"

info()  { printf '\033[0;34m•\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m!\033[0m %s\n' "$*"; }
die()   { printf '\033[0;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

cd "$ROOT_DIR"

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else die "Docker Compose nicht gefunden."; fi

info "Warte, bis MCP Gateway bereit ist…"
for i in $(seq 1 40); do
  docker exec mcp mcp_manage --getkey >/dev/null 2>&1 && break
  sleep 3
  [ "$i" -eq 40 ] && die "MCP Gateway wurde nicht rechtzeitig bereit. Prüfe: docker logs mcp"
done

MCP_KEY="$(docker exec mcp mcp_manage --getkey)"
[ -n "$MCP_KEY" ] || die "Konnte keinen MCP-API-Key auslesen."

if [ -f "$ENV_FILE" ] && grep -q '^MCP_API_KEY=' "$ENV_FILE"; then
  # bestehenden Eintrag ersetzen
  tmp="$(mktemp)"
  awk -v key="$MCP_KEY" '
    /^MCP_API_KEY=/ { print "MCP_API_KEY=" key; next }
    { print }
  ' "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
else
  printf '\n# Von scripts/wire-mcp.sh eingetragen (MCP-Gateway-API-Key für LiteLLM):\nMCP_API_KEY=%s\n' "$MCP_KEY" >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
ok "MCP-API-Key in .env eingetragen."

info "Starte LiteLLM neu, damit der Key übernommen wird…"
$DC -f "$COMPOSE_FILE" up -d litellm >/dev/null

info "Warte, bis LiteLLM wieder bereit ist…"
for i in $(seq 1 40); do
  if command -v curl >/dev/null 2>&1; then
    curl -sf "http://localhost:${PORT_LITELLM:-4000}/health/liveliness" >/dev/null 2>&1 && break
  else
    python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT_LITELLM:-4000}/health/liveliness')" >/dev/null 2>&1 && break
  fi
  sleep 3
done

ok "MCP Gateway ist mit LiteLLM verbunden."

# ── mcpo (MCP → OpenAPI, für Open WebUI) ────────────────────────────────────
info "Rendere mcpo/config.json (mit echtem Key statt Platzhalter)…"
TEMPLATE="$ROOT_DIR/mcpo/config.template.json"
RENDERED="$ROOT_DIR/mcpo/config.json"
if [ -f "$TEMPLATE" ]; then
  sed "s#__MCP_API_KEY__#${MCP_KEY}#" "$TEMPLATE" > "$RENDERED"
  chmod 600 "$RENDERED"
  ok "mcpo/config.json geschrieben (enthält den Key im Klartext, nicht committen — .gitignore deckt das ab)."

  info "Starte mcpo neu, damit die Konfiguration übernommen wird…"
  $DC -f "$COMPOSE_FILE" up -d mcpo >/dev/null

  info "Warte, bis mcpo bereit ist…"
  for i in $(seq 1 30); do
    if docker exec mcpo python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/docs')" >/dev/null 2>&1; then
      ok "mcpo ist bereit."
      break
    fi
    sleep 2
  done
else
  warn "mcpo/config.template.json nicht gefunden — mcpo-Schritt übersprungen."
fi

echo
echo "Prüfen (LiteLLM):        docker logs litellm | grep -i mcp"
echo "Prüfen (mcpo/Open WebUI): docker logs mcpo"
echo "Direkter Test:            docker exec mcp mcp_manage --getkey  (gleicher Key wie in .env)"
echo
echo "In Open WebUI einbinden: Admin-Einstellungen → Werkzeuge → Werkzeug-Server verwalten,"
echo "  URL: http://mcpo:8000/mcp_gateway   (Dateisystem, Web, GitHub, ...)"
echo "  URL: http://mcpo:8000/code_sandbox  (run_python, run_shell)"
