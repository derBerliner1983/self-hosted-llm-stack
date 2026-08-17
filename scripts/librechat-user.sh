#!/usr/bin/env bash
#
# Legt das erste LibreChat-Konto an, damit man sich nach der Installation
# direkt anmelden kann, statt sich erst selbst registrieren zu müssen.
#
# LibreChat bringt dafür ein eigenes Kommando mit:
#   npm run create-user -- <email> <name> <benutzername> <passwort> [--email-verified=…]
# (Reihenfolge aus config/create-user.js des Projekts.)
#
# Aufruf:
#   ./scripts/librechat-user.sh            Konto anlegen (falls noch keins da)
#   ./scripts/librechat-user.sh --show     nur die Zugangsdaten anzeigen
#   ./scripts/librechat-user.sh --force    auch anlegen, wenn schon Nutzer da sind
#
# Zugangsdaten stehen in der .env:
#   LIBRECHAT_ADMIN_EMAIL, LIBRECHAT_ADMIN_PASSWORD, LIBRECHAT_ADMIN_NAME
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'; c_blue=$'\033[0;34m'
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
info() { printf '%s•%s %s\n' "$c_blue" "$c_reset" "$1"; }
warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$1"; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$1"; }

MODE="create"
for a in "$@"; do
  case "$a" in
    --show)  MODE="show" ;;
    --force) MODE="force" ;;
    -h|--help) sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unbekannte Option: $a"; exit 2 ;;
  esac
done

cd "$ROOT_DIR" || exit 1
[ -f "$ENV_FILE" ] || { err "Keine .env gefunden — erst ./install.sh ausführen."; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

EMAIL="${LIBRECHAT_ADMIN_EMAIL:-}"
PASSWORD="${LIBRECHAT_ADMIN_PASSWORD:-}"
NAME="${LIBRECHAT_ADMIN_NAME:-Admin}"
USERNAME="${LIBRECHAT_ADMIN_USERNAME:-admin}"
PORT_LIBRECHAT="${PORT_LIBRECHAT:-3080}"

show_credentials() {
  local ip url
  url="${URL_LIBRECHAT:-}"
  if [ -z "$url" ]; then
    ip="$(ip -o -f inet addr show scope global 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1)"
    url="http://${ip:-<server-ip>}:${PORT_LIBRECHAT}"
  fi
  printf '\n%sLibreChat · Zugangsdaten%s\n' "$c_bold" "$c_reset"
  printf '  Adresse:    %s\n' "$url"
  printf '  E-Mail:     %s\n' "${EMAIL:-<nicht gesetzt>}"
  printf '  Passwort:   %s\n' "${PASSWORD:-<nicht gesetzt>}"
  printf '\n  %sPasswort nach der ersten Anmeldung in LibreChat ändern.%s\n' "$c_dim" "$c_reset"
  printf '  %sDie Registrierung ist standardmäßig zu (LIBRECHAT_ALLOW_REGISTRATION=false),%s\n' "$c_dim" "$c_reset"
  printf '  %sdamit sich niemand sonst ein Konto anlegen kann.%s\n' "$c_dim" "$c_reset"
}

if [ "$MODE" = "show" ]; then
  show_credentials
  exit 0
fi

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  err "LIBRECHAT_ADMIN_EMAIL/-PASSWORD fehlen in der .env."
  info "Nachtragen und erneut ausführen, oder ./install.sh laufen lassen."
  exit 1
fi
case "$EMAIL" in *@*) ;; *) err "LIBRECHAT_ADMIN_EMAIL braucht ein @: $EMAIL"; exit 1 ;; esac

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx librechat; then
  err "Der Container 'librechat' läuft nicht."
  info "Starten:  docker compose -f $COMPOSE_FILE up -d librechat librechat-mongo"
  exit 1
fi

# Auf die Datenbank warten — direkt nach 'up -d' ist Mongo oft noch nicht bereit,
# und create-user bricht dann mit einem Verbindungsfehler ab.
info "Warte auf die LibreChat-Datenbank…"
for _ in $(seq 1 30); do
  if docker exec librechat-mongo mongosh --quiet --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Gibt es schon Nutzer? Dann nicht ungefragt ein zweites Konto anlegen.
if [ "$MODE" != "force" ]; then
  if docker exec librechat npm run list-users --silent 2>/dev/null | grep -q '@'; then
    ok "Es gibt bereits mindestens ein LibreChat-Konto — nichts zu tun."
    show_credentials
    exit 0
  fi
fi

info "Lege das Konto '$EMAIL' an…"
# Ohne PIPESTATUS käme der Rückgabewert von sed und wäre immer 0 — der
# Fehlerzweig unten würde dann nie greifen.
docker exec librechat npm run create-user --silent -- \
  "$EMAIL" "$NAME" "$USERNAME" "$PASSWORD" --email-verified=true 2>&1 | sed 's/^/    /'
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  ok "LibreChat-Konto angelegt."
else
  warn "create-user meldete einen Fehler (existiert das Konto schon?)."
  info "Nutzer auflisten:  docker exec librechat npm run list-users"
fi

show_credentials
