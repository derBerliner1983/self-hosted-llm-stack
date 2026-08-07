#!/usr/bin/env bash
#
# Verdrahtet MCP Gateway mit LiteLLM.
#
# Das vanilla-LiteLLM-Image (im Gegensatz zu hwdsl2/litellm-server) teilt
# API-Keys nicht automatisch über Volumes. Dieses Skript holt den vom
# mcp-Container erzeugten API-Key, schreibt ihn als MCP_API_KEY in die .env
# und startet LiteLLM neu, damit litellm/config.yaml (mcp_servers.*.auth_value
# = os.environ/MCP_API_KEY) ihn übernimmt.
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
echo
echo "Prüfen: docker logs litellm | grep -i mcp"
echo "Direkter Test: docker exec mcp mcp_manage --getkey  (gleicher Key wie in .env)"
