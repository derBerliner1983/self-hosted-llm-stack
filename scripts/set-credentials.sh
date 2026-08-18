#!/usr/bin/env bash
#
# Eigenen Benutzernamen und ein eigenes Passwort für einen Dienst festlegen.
#
# Der wichtige Unterschied zu den erzeugten Standard-Zugangsdaten: ein selbst
# gewähltes Passwort wird NICHT in die .env geschrieben. Du kennst es ja — es
# dort im Klartext abzulegen brächte nichts als ein weiteres Risiko. In der
# .env bleibt nur der Benutzername und die Notiz, dass ein eigenes Passwort
# gesetzt wurde; die Anzeige der Zugangsdaten sagt dann genau das.
#
# Aufruf:
#   ./scripts/set-credentials.sh librechat
#   ./scripts/set-credentials.sh syncthing
#   ./scripts/set-credentials.sh open-webui
#
# Zurück zum erzeugten Standard-Passwort:
#   ./scripts/set-credentials.sh <dienst> --reset
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

SERVICE=""; RESET=0
for a in "$@"; do
  case "$a" in
    --reset) RESET=1 ;;
    -h|--help) sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) err "Unbekannte Option: $a"; exit 2 ;;
    *)  SERVICE="$a" ;;
  esac
done
[ -n "$SERVICE" ] || { err "Kein Dienst angegeben. Möglich: librechat, syncthing, open-webui"; exit 2; }

cd "$ROOT_DIR" || exit 1
[ -f "$ENV_FILE" ] || { err "Keine .env gefunden — erst ./install.sh ausführen."; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
# shellcheck disable=SC1091
. "$SCRIPT_DIR/env-lib.sh"

running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"; }

# Benutzername und Passwort abfragen. Das Passwort wird ohne Echo gelesen und
# zur Sicherheit zweimal verlangt — ein Tippfehler würde sonst erst beim
# nächsten Anmeldeversuch auffallen, und dann kennt ihn niemand mehr.
NEWUSER=""; NEWPASS=""
ask_credentials() {
  local label="$1" current="$2" minlen="${3:-8}" pass2
  printf '\n%s%s · eigene Zugangsdaten festlegen%s\n\n' "$c_bold" "$label" "$c_reset"
  printf '  %sDas Passwort wird NICHT in der .env gespeichert.%s\n' "$c_dim" "$c_reset"
  printf '  %sNotier es dir — es lässt sich später nicht mehr anzeigen.%s\n\n' "$c_dim" "$c_reset"

  printf '  %s [%s]: ' "$4" "$current"
  read -r NEWUSER || NEWUSER=""
  [ -z "$NEWUSER" ] && NEWUSER="$current"

  while :; do
    printf '  Passwort (mind. %s Zeichen): ' "$minlen"
    read -rs NEWPASS || NEWPASS=""; echo
    if [ "${#NEWPASS}" -lt "$minlen" ]; then
      warn "Zu kurz — mindestens $minlen Zeichen."
      continue
    fi
    printf '  Passwort wiederholen: '
    read -rs pass2 || pass2=""; echo
    if [ "$NEWPASS" != "$pass2" ]; then
      warn "Die Eingaben stimmen nicht überein."
      continue
    fi
    break
  done
}

# In der .env festhalten, DASS ein eigenes Passwort gilt — nicht welches.
mark_own_password() {
  local passvar="$1" markvar="$2"
  env_set "$passvar" ""                                   # erzeugtes Passwort verwerfen
  env_set "$markvar" "$(date '+%Y-%m-%dT%H:%M')"
  ok "In der .env vermerkt: eigenes Passwort (der Wert selbst steht dort nicht)."
}

# Zurück auf ein erzeugtes Passwort: Markierung weg, neues erzeugen, anwenden.
reset_to_generated() {
  local passvar="$1" markvar="$2" newpw
  newpw="$(env_rand 20)"
  env_set "$passvar" "$newpw"
  env_set "$markvar" ""
  export "${passvar}=${newpw}"
  NEWPASS="$newpw"
  info "Neues Passwort erzeugt — es steht danach in der .env und in den Zugangsdaten."
}

# ── LibreChat ───────────────────────────────────────────────────────────────
do_librechat() {
  running librechat || { err "Der Container 'librechat' läuft nicht."; return 1; }
  local email="${LIBRECHAT_ADMIN_EMAIL:-admin@stack.local}"

  if [ "$RESET" -eq 1 ]; then
    reset_to_generated LIBRECHAT_ADMIN_PASSWORD LIBRECHAT_ADMIN_PASSWORD_SET
    NEWUSER="$email"
  else
    ask_credentials "LibreChat" "$email" 8 "E-Mail"
    case "$NEWUSER" in *@*) ;; *) err "Die E-Mail braucht ein @: $NEWUSER"; return 1 ;; esac
  fi

  # Gibt es das Konto? Wenn nein, anlegen statt Passwort zu ändern.
  if docker exec librechat npm run list-users --silent 2>/dev/null | grep -qF "$NEWUSER"; then
    # reset-password fragt interaktiv nach E-Mail, Passwort und Wiederholung
    # (config/reset-password.js) — genau diese drei Zeilen bekommt es.
    info "Ändere das Passwort für $NEWUSER…"
    printf '%s\n%s\n%s\n' "$NEWUSER" "$NEWPASS" "$NEWPASS" \
      | docker exec -i librechat npm run reset-password --silent >/tmp/lc-pw.out 2>&1
    if grep -q "successfully reset" /tmp/lc-pw.out; then
      ok "Passwort geändert. Alle bestehenden Anmeldungen sind ungültig."
    else
      err "Ändern fehlgeschlagen:"; sed 's/^/    /' /tmp/lc-pw.out | tail -5; rm -f /tmp/lc-pw.out; return 1
    fi
    rm -f /tmp/lc-pw.out
  else
    info "Konto $NEWUSER existiert nicht — lege es an…"
    if docker exec librechat npm run create-user --silent -- \
         "$NEWUSER" "${LIBRECHAT_ADMIN_NAME:-Admin}" "${LIBRECHAT_ADMIN_USERNAME:-admin}" \
         "$NEWPASS" --email-verified=true >/dev/null 2>&1; then
      ok "Konto angelegt."
    else
      err "Anlegen fehlgeschlagen."; return 1
    fi
  fi

  env_set LIBRECHAT_ADMIN_EMAIL "$NEWUSER"
  [ "$RESET" -eq 1 ] || mark_own_password LIBRECHAT_ADMIN_PASSWORD LIBRECHAT_ADMIN_PASSWORD_SET
}

# ── Syncthing ───────────────────────────────────────────────────────────────
do_syncthing() {
  running syncthing || { err "Der Container 'syncthing' läuft nicht."; return 1; }

  if [ "$RESET" -eq 1 ]; then
    reset_to_generated SYNCTHING_GUI_PASSWORD SYNCTHING_GUI_PASSWORD_SET
    NEWUSER="${SYNCTHING_GUI_USER:-admin}"
  else
    ask_credentials "Syncthing" "${SYNCTHING_GUI_USER:-admin}" 1 "Benutzername"
  fi

  # Passwort über die Standardeingabe ("-"), damit es nicht in der
  # Prozessliste des Hosts auftaucht.
  info "Setze Benutzer und Passwort der Oberfläche…"
  if printf '%s' "$NEWPASS" | docker exec -i syncthing \
       syncthing generate --config=/var/syncthing/config \
       --gui-user="$NEWUSER" --gui-password=- >/dev/null 2>&1; then
    if docker restart syncthing >/dev/null 2>&1; then
      ok "Gesetzt, Syncthing neu gestartet."
    else
      warn "Gesetzt, aber Neustart fehlgeschlagen: docker restart syncthing"
    fi
  else
    err "syncthing generate ist fehlgeschlagen."; return 1
  fi

  env_set SYNCTHING_GUI_USER "$NEWUSER"
  [ "$RESET" -eq 1 ] || mark_own_password SYNCTHING_GUI_PASSWORD SYNCTHING_GUI_PASSWORD_SET
}

# ── Open WebUI ──────────────────────────────────────────────────────────────
do_open_webui() {
  if [ "$RESET" -eq 1 ]; then
    reset_to_generated OPENWEBUI_ADMIN_PASSWORD OPENWEBUI_ADMIN_PASSWORD_SET
    env_set OPENWEBUI_ADMIN_EMAIL "${OPENWEBUI_ADMIN_EMAIL:-admin@stack.local}"
    info "Gilt für ein NEU anzulegendes Konto:"
    info "  ./scripts/service-credentials.sh open-webui --create"
    return 0
  fi

  ask_credentials "Open WebUI" "${OPENWEBUI_ADMIN_EMAIL:-admin@stack.local}" 8 "E-Mail"
  case "$NEWUSER" in *@*) ;; *) err "Die E-Mail braucht ein @: $NEWUSER"; return 1 ;; esac

  env_set OPENWEBUI_ADMIN_EMAIL "$NEWUSER"
  mark_own_password OPENWEBUI_ADMIN_PASSWORD OPENWEBUI_ADMIN_PASSWORD_SET

  # Ehrlich bleiben: Open WebUI bietet keinen Weg, das Passwort eines
  # BESTEHENDEN Kontos von aussen zu ändern. Anlegen geht, ändern nicht.
  if running open-webui && docker exec open-webui sh -c \
       'test -f /app/backend/data/webui.db' 2>/dev/null; then
    warn "Ein bestehendes Open-WebUI-Konto lässt sich von hier NICHT ändern."
    info "Das Passwort änderst du in der Oberfläche selbst:"
    info "  Profil (unten links) → Einstellungen → Konto → Passwort ändern"
    info "Diese Werte gelten für ein neu angelegtes Konto."
  fi
}

case "$SERVICE" in
  librechat)  do_librechat  || exit 1 ;;
  syncthing)  do_syncthing  || exit 1 ;;
  open-webui) do_open_webui || exit 1 ;;
  litellm)
    err "LiteLLM hat kein eigenes Passwort — der Master-Key IST die Anmeldung."
    info "Ihn zu tauschen trifft alle Clients (Open WebUI, LibreChat, Claude Code)."
    info "Wenn du das wirklich willst: LITELLM_MASTER_KEY in der .env ändern,"
    info "dann 'docker compose -f $COMPOSE_FILE up -d --force-recreate' und"
    info "anschliessend ./scripts/wire-mcp.sh erneut ausführen."
    exit 1 ;;
  *)
    err "Für '$SERVICE' gibt es nichts einzustellen."
    info "Möglich: librechat, syncthing, open-webui"
    exit 2 ;;
esac

printf '\n'
if [ "$RESET" -eq 1 ]; then
  ok "Zurück auf ein erzeugtes Passwort — anzeigen mit:"
  printf '    ./scripts/service-credentials.sh %s\n' "$SERVICE"
else
  ok "Fertig. Benutzername: $NEWUSER"
  printf '  %sDas Passwort steht nirgends gespeichert — nur du kennst es.%s\n' "$c_dim" "$c_reset"
  printf '  %sZurück zum erzeugten Standard: ./scripts/set-credentials.sh %s --reset%s\n' \
    "$c_dim" "$SERVICE" "$c_reset"
fi
