#!/usr/bin/env bash
#
# Startet Open Interpreter gegen das LiteLLM dieses Stacks.
#
# Aufruf:
#   ./scripts/interpreter.sh                    interaktive Sitzung
#   ./scripts/interpreter.sh --build            Image (neu) bauen, dann starten
#   ./scripts/interpreter.sh -y                 ohne Rückfrage ausführen lassen
#   ./scripts/interpreter.sh --model ollama/qwen2.5:14b
#
# Alle Argumente werden an Open Interpreter durchgereicht; nur --build wird
# vorher abgefangen. Die Voreinstellungen (Modell, Kontextfenster) stehen in
# der .env: INTERPRETER_MODEL, INTERPRETER_CONTEXT_WINDOW, INTERPRETER_MAX_TOKENS.
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'

cd "$ROOT_DIR"

[ -f "$COMPOSE_FILE" ] || { printf '%sCompose-Datei nicht gefunden: %s%s\n' "$c_red" "$COMPOSE_FILE" "$c_reset" >&2; exit 1; }
[ -f .env ] || { printf '%sKeine .env gefunden — erst ./install.sh ausführen.%s\n' "$c_red" "$c_reset" >&2; exit 1; }

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else printf '%sDocker Compose nicht gefunden.%s\n' "$c_red" "$c_reset" >&2; exit 1; fi

BUILD=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--build" ]; then BUILD=1; else ARGS+=("$a"); fi
done

# Image vorhanden? Beim allerersten Start muss gebaut werden — 'compose run'
# täte das zwar auch, aber ohne jeden Hinweis, warum es minutenlang hängt.
if [ "$BUILD" -eq 1 ] || ! $DC -f "$COMPOSE_FILE" images interpreter 2>/dev/null | grep -q interpreter; then
  printf '%sBaue das Open-Interpreter-Image (beim ersten Mal ein paar Minuten)…%s\n' "$c_dim" "$c_reset"
  $DC -f "$COMPOSE_FILE" --profile cli build interpreter
fi

# LiteLLM muss laufen, sonst startet Open Interpreter und scheitert erst beim
# ersten Prompt mit einer Verbindungsmeldung, die niemand zuordnen kann.
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx litellm; then
  printf '%sLiteLLM läuft nicht — starte es…%s\n' "$c_yellow" "$c_reset"
  $DC -f "$COMPOSE_FILE" up -d litellm
fi

printf '%sArbeitsverzeichnis im Container: /work (bleibt erhalten). Beenden mit Strg-C.%s\n\n' "$c_dim" "$c_reset"

# --rm: kein Container-Friedhof. --profile cli, weil der Dienst sonst nicht
# sichtbar ist. "${ARGS[@]+"${ARGS[@]}"}" statt "${ARGS[@]}": bei leerem Array
# und 'set -u' bricht die einfache Form in älteren bash-Versionen ab.
exec $DC -f "$COMPOSE_FILE" --profile cli run --rm interpreter "${ARGS[@]+"${ARGS[@]}"}"
