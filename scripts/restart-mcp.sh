#!/usr/bin/env bash
#
# Startet die MCP-Dienste in der richtigen Reihenfolge neu — und vor allem
# 'mcpo' IMMER zuletzt.
#
# Hintergrund: mcpo hält je eine laufende Session zu 'mcp' und zu
# 'sandbox-mcp'. Wird einer der beiden neu gestartet oder neu erstellt,
# reißt diese Session — mcpo merkt das nicht und verbindet sich auch nicht
# neu. Werkzeugaufrufe aus Open WebUI scheitern dann mit
#
#   500: {'message': 'MCP session is not available'}
#
# bis mcpo selbst neu gestartet wird. Genau das nimmt dieses Skript ab, damit
# man nicht jedes Mal daran denken muss.
#
# Aufruf:
#   ./scripts/restart-mcp.sh              # mcp + sandbox-mcp + mcpo neu starten
#   ./scripts/restart-mcp.sh --build      # vorher die lokal gebauten Images neu bauen
#   ./scripts/restart-mcp.sh --mcpo-only  # nur mcpo (nach Änderungen an mcp_settings.json)
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"

info() { printf '\033[0;34m•\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m!\033[0m %s\n' "$*"; }

BUILD=0
MCPO_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --build)     BUILD=1 ;;
    --mcpo-only) MCPO_ONLY=1 ;;
    -h|--help)
      sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unbekannte Option: $arg (siehe --help)" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

# Wartet, bis ein Dienst laut Compose den Zustand "healthy" meldet. Dienste
# ohne Healthcheck laufen hier nicht in eine Endlosschleife: sobald der
# Container überhaupt läuft und kein Healthcheck definiert ist, gilt er als
# fertig.
wait_healthy() {
  local svc="$1" tries="${2:-40}" cid state health
  for _ in $(seq 1 "$tries"); do
    cid="$(compose ps -q "$svc" 2>/dev/null || true)"
    if [ -n "$cid" ]; then
      state="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo '')"
      health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo 'none')"
      if [ "$state" = "running" ] && { [ "$health" = "healthy" ] || [ "$health" = "none" ]; }; then
        return 0
      fi
    fi
    sleep 2
  done
  warn "$svc wurde nicht rechtzeitig bereit — trotzdem weiter."
  return 0
}

if [ "$MCPO_ONLY" -eq 0 ]; then
  if [ "$BUILD" -eq 1 ]; then
    # Nur diese beiden Dienste werden aus lokalem Quellcode gebaut; alle
    # anderen kommen als fertiges Image aus einer Registry.
    info "Baue die lokal gebauten Images neu (vault-bridge, sandbox-mcp)…"
    compose build vault-bridge sandbox-mcp
    info "Erzeuge vault-bridge und sandbox-mcp mit dem neuen Stand neu…"
    compose up -d vault-bridge sandbox-mcp
  else
    info "Starte mcp und sandbox-mcp neu…"
    compose restart mcp sandbox-mcp
  fi

  info "Warte, bis mcp und sandbox-mcp bereit sind…"
  wait_healthy mcp
  wait_healthy sandbox-mcp
fi

# Der eigentliche Punkt dieses Skripts: mcpo kommt zuletzt, damit es seine
# Sessions gegen frisch gestartete Gegenstellen neu aufbaut.
info "Starte mcpo neu (zuletzt, damit die Sessions wieder stehen)…"
compose restart mcpo
wait_healthy mcpo

ok "Fertig. Werkzeuge sollten in Open WebUI wieder funktionieren."
echo
echo "Gegenprobe ohne Modell dazwischen:"
echo "  docker exec mcp curl -s -X POST http://mcpo:8000/mcp_gateway/filesystem-list_directory \\"
echo "    -H 'Content-Type: application/json' -d '{\"path\":\"/vault\"}'"
