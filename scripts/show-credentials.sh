#!/usr/bin/env bash
#
# Zeigt alle Zugangsdaten des ROCm-Stacks an: URLs, LiteLLM-Master-Key,
# Postgres-Passwort und den WebUI-Secret-Key. Liest sie direkt aus der
# lokalen .env — kein 'docker exec ... _manage' nötig (das gibt es im
# vanilla-Ollama/-LiteLLM-Image nicht, nur in den alten hwdsl2-Images).
#
# Aufruf: ./scripts/show-credentials.sh
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_blue=$'\033[0;34m'

[ -f "$ENV_FILE" ] || { echo "Keine .env gefunden unter $ENV_FILE — erst ./install.sh ausführen." >&2; exit 1; }
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

PORT_WEBUI="${PORT_WEBUI:-3001}"
PORT_LITELLM="${PORT_LITELLM:-4000}"
PORT_DASHBOARD="${PORT_DASHBOARD:-8600}"

IP="$(ip -o -f inet addr show scope global 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1 || true)"
IP="${IP:-<server-ip>}"

printf '%s' "$c_bold"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Self-Hosted AI Stack · Zugangsdaten                ║"
echo "╚══════════════════════════════════════════════════════╝"
printf '%s\n' "$c_reset"

printf '%sDienste%s\n' "$c_bold" "$c_reset"
printf '  Dashboard      http://%s:%s\n' "$IP" "$PORT_DASHBOARD"
printf '  Chat (WebUI)   http://%s:%s\n' "$IP" "$PORT_WEBUI"
printf '  LiteLLM-UI     http://%s:%s/ui\n' "$IP" "$PORT_LITELLM"
echo

printf '%sLiteLLM%s\n' "$c_bold" "$c_reset"
printf '  Login Admin-UI:   Benutzername %sadmin%s, Passwort = Master-Key unten\n' "$c_bold" "$c_reset"
printf '  Master-Key:       %s\n' "${LITELLM_MASTER_KEY:-<nicht gesetzt>}"
echo

printf '%sPostgreSQL%s\n' "$c_bold" "$c_reset"
printf '  Benutzer:   litellm\n'
printf '  Passwort:   %s\n' "${POSTGRES_PASSWORD:-<nicht gesetzt>}"
echo

printf '%sOpen WebUI%s\n' "$c_bold" "$c_reset"
printf '  %sKein vorgegebenes Passwort:%s der erste Account, den du unter\n' "$c_dim" "$c_reset"
printf '  http://%s:%s registrierst, wird automatisch Admin.\n' "$IP" "$PORT_WEBUI"
printf '  Interner Secret-Key (Sessions/Cookies): %s\n' "${WEBUI_SECRET_KEY:-<nicht gesetzt>}"
echo

printf '%sMCP Gateway%s\n' "$c_bold" "$c_reset"
if [ -n "${MCP_API_KEY:-}" ]; then
  printf '  API-Key (bei LiteLLM hinterlegt):   %s\n' "$MCP_API_KEY"
else
  printf '  %sNoch nicht verdrahtet.%s Ausführen: ./scripts/wire-mcp.sh\n' "$c_dim" "$c_reset"
fi
echo

printf '%s%sHinweis:%s Diese Werte stehen im Klartext in %s.env%s — Datei nicht committen/teilen.\n' \
  "$c_blue" "$c_bold" "$c_reset$c_dim" "$c_bold" "$c_reset"
