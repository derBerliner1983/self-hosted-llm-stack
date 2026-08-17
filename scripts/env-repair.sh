#!/usr/bin/env bash
#
# .env auffrischen: sichert die alte Datei und schreibt eine neue, vollständige
# AUF GRUNDLAGE DER ALTEN.
#
# Alle vorhandenen Werte werden übernommen — auch solche, die dieses Skript gar
# nicht kennt (selbst gesetzte Adressen, geänderte Ports, eigene Einträge). Die
# landen am Ende in einem eigenen Abschnitt, statt verloren zu gehen. Fehlendes
# wird ergänzt, Passwörter dabei einmalig zufällig erzeugt.
#
# Aufruf:
#   ./scripts/env-repair.sh            neu aufbauen (mit Sicherung)
#   ./scripts/env-repair.sh --check    nur prüfen, nichts ändern
#
# Rückgabe bei --check: 0 = vollständig, 1 = es fehlt etwas.
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'; c_blue=$'\033[0;34m'
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
info() { printf '%s•%s %s\n' "$c_blue" "$c_reset" "$1"; }
warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$1"; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$1"; }

CHECK_ONLY=0
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    -h|--help) sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unbekannte Option: $a"; exit 2 ;;
  esac
done

# shellcheck disable=SC1091
. "$SCRIPT_DIR/env-lib.sh"

[ -f "$ENV_FILE" ] || { err "Keine .env gefunden — erst ./install.sh ausführen."; exit 1; }

# ── Aufbau der .env ─────────────────────────────────────────────────────────
# "#S <Titel>" beginnt einen Abschnitt, "#K <Text>" ist ein Kommentar.
# Sonst KEY=Vorgabe. Besondere Vorgaben:
#   @rand20 / @rand32  einmalig erzeugen, wenn der Wert fehlt
#   @keep              nur übernehmen, wenn vorhanden (Secrets aus install.sh)
# Maßgeblich für eine Neuinstallation bleibt install.sh; hier steht, was der
# laufende Betrieb braucht.
SPEC='
#S Grundlagen
COMPOSE_FILE=docker-compose.rocm.yml
#K Erkennt das Menue die falsche IP (mehrere Netzwerkkarten), hier eintragen.
STACK_HOST=

#S Ports
PORT_WEBUI=3001
PORT_LIBRECHAT=3080
PORT_LITELLM=4000
PORT_DASHBOARD=8600
PORT_VAULT_BRIDGE=8700
PORT_SYNCTHING_GUI=8384
PORT_MCPO=8800
PORT_MCP=3000

#S Secrets (von install.sh erzeugt)
POSTGRES_PASSWORD=@keep
LITELLM_MASTER_KEY=@keep
WEBUI_SECRET_KEY=@keep
MCP_API_KEY=@keep

#S Wissensdatenbank
#K ro = die KI darf nur lesen, rw = auch schreiben.
MCP_VAULT_MOUNT_MODE=ro
MCP_FILESYSTEM_DIRS=/vault,/workspace

#S LibreChat
#K CREDS_KEY braucht 64 Hex-Zeichen, CREDS_IV genau 32 - LibreChat prueft das
#K beim Start. Nicht nachtraeglich aendern, sonst sind gespeicherte
#K Zugangsdaten unlesbar und alle Anmeldungen fliegen raus.
LIBRECHAT_CREDS_KEY=@keep
LIBRECHAT_CREDS_IV=@keep
LIBRECHAT_JWT_SECRET=@keep
LIBRECHAT_JWT_REFRESH_SECRET=@keep
LIBRECHAT_ALLOW_REGISTRATION=false
LIBRECHAT_ADMIN_EMAIL=admin@stack.local
LIBRECHAT_ADMIN_NAME=Admin
LIBRECHAT_ADMIN_USERNAME=admin
LIBRECHAT_ADMIN_PASSWORD=@rand20

#S Open WebUI
#K Der erste registrierte Account wird automatisch Admin. Anlegen mit
#K   ./scripts/service-credentials.sh open-webui --create
OPENWEBUI_ADMIN_EMAIL=admin@stack.local
OPENWEBUI_ADMIN_NAME=Admin
OPENWEBUI_ADMIN_PASSWORD=@rand20

#S Syncthing
#K Die Oberflaeche hat ab Werk KEIN Passwort. Setzen mit
#K   ./scripts/service-credentials.sh syncthing --create
SYNCTHING_GUI_USER=admin
SYNCTHING_GUI_PASSWORD=@rand20

#S Open Interpreter (CLI, optional)
INSTALL_OPEN_INTERPRETER=no
INTERPRETER_MODEL=ollama/gemma3:12b
INTERPRETER_CONTEXT_WINDOW=16384
INTERPRETER_MAX_TOKENS=4096
OPEN_INTERPRETER_VERSION=0.4.3

#S Eigene Adressen der Dienste
#K Leer = aus IP und Port dieses Rechners gebildet. Trag hier den Namen ein,
#K unter dem ein Dienst von aussen erreichbar ist (Reverse-Proxy). Das Menue
#K zeigt und setzt diese Werte ebenfalls.
#K   URL_OPEN_WEBUI=https://chat.example.com
URL_OPEN_WEBUI=
URL_LIBRECHAT=
URL_LITELLM=
URL_DASHBOARD=
URL_VAULT_BRIDGE=
URL_SYNCTHING=
URL_MCPO=
URL_MCP=

#S Firewall
LAN_SUBNET=@keep
'

# ── Alte Werte einlesen ─────────────────────────────────────────────────────
declare -A OLD=()
OLD_ORDER=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in *=*) ;; *) continue ;; esac
  k="${line%%=*}"
  # Nur plausible Schlüsselnamen — alles andere ist keine Zuweisung.
  case "$k" in [A-Za-z_]*) ;; *) continue ;; esac
  OLD["$k"]="${line#*=}"
  OLD_ORDER+=("$k")
done < "$ENV_FILE"

# ── Was fehlt? ──────────────────────────────────────────────────────────────
missing=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  k="${line%%=*}"; v="${line#*=}"
  [ "$v" = "@keep" ] && continue          # darf fehlen
  [ -n "${OLD[$k]+x}" ] || missing+=("$k")
done <<EOF
$SPEC
EOF

if [ "${#missing[@]}" -eq 0 ]; then
  ok "Die .env ist vollständig — nichts zu tun."
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  warn "In der .env fehlen ${#missing[@]} Einträge:"
  printf '    %s\n' "${missing[@]}"
  info "Neu aufbauen:  ./scripts/env-repair.sh"
  exit 1
fi

# ── Sichern ─────────────────────────────────────────────────────────────────
backup="${ENV_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
if cp -p "$ENV_FILE" "$backup" && chmod 600 "$backup" 2>/dev/null; then
  ok "Sicherung angelegt: $(basename "$backup")"
else
  err "Sicherung fehlgeschlagen — es wird nichts geändert."
  exit 1
fi

# ── Neue .env schreiben ─────────────────────────────────────────────────────
tmp="$(mktemp "${ENV_FILE}.XXXXXX")" || { err "Kann keine temporäre Datei anlegen."; exit 1; }
chmod 600 "$tmp"

{
  printf '# Self-Hosted AI Stack — Konfiguration\n'
  printf '# Neu aufgebaut am %s aus der bisherigen .env.\n' "$(date '+%Y-%m-%d %H:%M')"
  printf '# Enthält Secrets — nicht committen, nicht weitergeben.\n'
} > "$tmp"

declare -A USED=()
added=()
kept=0
while IFS= read -r line; do
  case "$line" in
    '') continue ;;
    '#S '*) printf '\n# ── %s ────────────────────────\n' "${line#\#S }" >> "$tmp"; continue ;;
    '#K '*) printf '# %s\n' "${line#\#K }" >> "$tmp"; continue ;;
    '#'*)   continue ;;
  esac
  k="${line%%=*}"; v="${line#*=}"
  USED["$k"]=1
  if [ -n "${OLD[$k]+x}" ]; then
    printf '%s=%s\n' "$k" "${OLD[$k]}" >> "$tmp"      # alten Wert übernehmen
    kept=$((kept+1))
    continue
  fi
  case "$v" in
    @keep)   continue ;;                              # nicht vorhanden -> weglassen
    @rand20) v="$(env_rand 20)" ;;
    @rand32) v="$(env_rand 32)" ;;
  esac
  printf '%s=%s\n' "$k" "$v" >> "$tmp"
  added+=("$k")
done <<EOF
$SPEC
EOF

# Alles, was dieses Skript nicht kennt, bleibt erhalten — genau deshalb wird
# die alte Datei gelesen und nicht einfach eine Vorlage hingelegt.
own=()
for k in "${OLD_ORDER[@]}"; do
  [ -n "${USED[$k]+x}" ] && continue
  own+=("$k")
done
if [ "${#own[@]}" -gt 0 ]; then
  {
    printf '\n# ── Eigene Einträge (aus der bisherigen .env übernommen) ─────\n'
    for k in "${own[@]}"; do printf '%s=%s\n' "$k" "${OLD[$k]}"; done
  } >> "$tmp"
fi

mv "$tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE" 2>/dev/null || true

ok "Neue .env geschrieben."
printf '  %sÜbernommen:%s %d Werte' "$c_dim" "$c_reset" "$kept"
[ "${#own[@]}" -gt 0 ] && printf ' (davon %d eigene, unverändert am Ende)' "${#own[@]}"
printf '\n'
if [ "${#added[@]}" -gt 0 ]; then
  printf '  %sNeu ergänzt:%s %d\n' "$c_dim" "$c_reset" "${#added[@]}"
  printf '    %s\n' "${added[@]}"
fi

printf '\n%sHinweis:%s Neu erzeugte Passwörter gelten erst, wenn das jeweilige\n' "$c_bold" "$c_reset"
printf 'Konto damit angelegt wird:\n'
printf '  ./scripts/service-credentials.sh librechat --create\n'
printf '  ./scripts/service-credentials.sh open-webui --create\n'
printf '  ./scripts/service-credentials.sh syncthing --create\n'
printf '\n%sAlle Zugangsdaten:%s ./scripts/service-credentials.sh\n' "$c_dim" "$c_reset"
printf '%sAlte Fassung:%s     %s\n' "$c_dim" "$c_reset" "$backup"
