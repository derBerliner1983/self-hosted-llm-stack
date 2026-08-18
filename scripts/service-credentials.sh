#!/usr/bin/env bash
#
# Zugangsdaten aller Dienste an einer Stelle — und, wo der Dienst das hergibt,
# das Standard-Konto gleich anlegen.
#
# Aufruf:
#   ./scripts/service-credentials.sh                    alle Dienste
#   ./scripts/service-credentials.sh librechat          nur dieser
#   ./scripts/service-credentials.sh librechat --create Konto anlegen
#
# Konto anlegen können: librechat, open-webui, syncthing.
# Bei allen anderen gibt es nichts anzulegen — dort steht der Zugang fest
# (LiteLLM: Master-Key) oder es gibt gar keine Anmeldung (Dashboard, mcpo).
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

WANT=""; CREATE=0
for a in "$@"; do
  case "$a" in
    --create) CREATE=1 ;;
    -h|--help) sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) err "Unbekannte Option: $a"; exit 2 ;;
    *)  WANT="$a" ;;
  esac
done

cd "$ROOT_DIR" || exit 1
[ -f "$ENV_FILE" ] || { err "Keine .env gefunden — erst ./install.sh ausführen."; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# shellcheck disable=SC1091
. "$SCRIPT_DIR/env-lib.sh"

# Zugangsdaten, die noch nicht in der .env stehen, hier nachtragen statt
# "<nicht gesetzt>" anzuzeigen. Ältere Installationen kennen diese Schlüssel
# nicht — sie kamen erst später dazu, und install.sh schreibt sie nur beim
# eigenen Lauf. Ohne das Nachtragen stünde man vor leeren Feldern und wüsste
# nicht, warum.
# Wurde für einen Dienst ein EIGENES Passwort gesetzt, steht es bewusst nicht
# in der .env. Dann darf hier auch keines nacherzeugt werden — sonst stünde ein
# Wert da, mit dem sich niemand anmelden kann.
own_password() {
  local mark="$1"
  [ -n "${!mark:-}" ]
}

ensure_credentials() {
  env_ensure LIBRECHAT_ADMIN_EMAIL    "admin@stack.local" || true
  env_ensure LIBRECHAT_ADMIN_NAME     "Admin"             || true
  env_ensure LIBRECHAT_ADMIN_USERNAME "admin"             || true
  own_password LIBRECHAT_ADMIN_PASSWORD_SET || env_ensure LIBRECHAT_ADMIN_PASSWORD "$(env_rand 20)" || true
  env_ensure OPENWEBUI_ADMIN_EMAIL    "admin@stack.local" || true
  env_ensure OPENWEBUI_ADMIN_NAME     "Admin"             || true
  own_password OPENWEBUI_ADMIN_PASSWORD_SET || env_ensure OPENWEBUI_ADMIN_PASSWORD "$(env_rand 20)" || true
  env_ensure SYNCTHING_GUI_USER       "admin"             || true
  own_password SYNCTHING_GUI_PASSWORD_SET || env_ensure SYNCTHING_GUI_PASSWORD "$(env_rand 20)" || true
}
ensure_credentials
NEWLY_ADDED="$ENV_ADDED"

HOST_IP="${STACK_HOST:-}"
[ -z "$HOST_IP" ] && HOST_IP="$(ip -o -f inet addr show scope global 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1)"
HOST_IP="${HOST_IP:-<server-ip>}"

# Adresse: eine in der .env hinterlegte URL_* hat Vorrang (Reverse-Proxy).
addr() {
  local var port="$2" path="${3:-}"
  var="URL_$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"
  else printf 'http://%s:%s%s' "$HOST_IP" "$port" "$path"; fi
}

running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"; }

head_of() { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_reset"; }
row()     { printf '  %-12s %s\n' "$1" "$2"; }

# Passwortzeile: entweder der erzeugte Wert, oder — bei selbst gesetztem
# Passwort — der Hinweis darauf. Der Wert selbst wird bewusst nicht
# gespeichert und kann deshalb auch nicht angezeigt werden.
pwrow() {
  local value="$1" mark="$2"
  if [ -n "${!mark:-}" ]; then
    printf '  %-12s %s(%s, nicht gespeichert)%s\n' \
      "Passwort:" "$c_dim" "selbst gesetzt am ${!mark}" "$c_reset"
    printf '  %sZurück zum erzeugten Standard: ./scripts/set-credentials.sh <dienst> --reset%s\n' \
      "$c_dim" "$c_reset"
  else
    printf '  %-12s %s\n' "Passwort:" "${value:-<nicht gesetzt>}"
  fi
}
note()    { printf '  %s%s%s\n' "$c_dim" "$1" "$c_reset"; }

# ── Anzeigen ────────────────────────────────────────────────────────────────
show_open_webui() {
  head_of "Open WebUI"
  row "Adresse:"  "$(addr open-webui "${PORT_WEBUI:-3001}")"
  if [ -n "${OPENWEBUI_ADMIN_EMAIL:-}" ]; then
    row "E-Mail:"   "$OPENWEBUI_ADMIN_EMAIL"
    pwrow "${OPENWEBUI_ADMIN_PASSWORD:-}" OPENWEBUI_ADMIN_PASSWORD_SET
    note "Konto anlegen (falls noch nicht geschehen): --create"
    fresh_note OPENWEBUI_ADMIN_PASSWORD
  else
    note "Kein Konto hinterlegt. Open WebUI macht den ERSTEN registrierten"
    note "Account automatisch zum Admin — im Browser registrieren."
  fi
}

# Passwort gerade erst erzeugt? Dann passt es nicht zu einem Konto, das es
# vielleicht schon gibt — das muss dabeistehen, sonst probiert man vergeblich.
fresh_note() {
  case " $NEWLY_ADDED " in
    *" $1 "*) note "Passwort gerade erzeugt — gilt erst, wenn das Konto damit angelegt wird." ;;
  esac
}

show_librechat() {
  head_of "LibreChat"
  row "Adresse:"  "$(addr librechat "${PORT_LIBRECHAT:-3080}")"
  row "E-Mail:"   "${LIBRECHAT_ADMIN_EMAIL:-<nicht gesetzt>}"
  pwrow "${LIBRECHAT_ADMIN_PASSWORD:-}" LIBRECHAT_ADMIN_PASSWORD_SET
  note "Registrierung ist zu (LIBRECHAT_ALLOW_REGISTRATION=false)."
  fresh_note LIBRECHAT_ADMIN_PASSWORD
}

show_litellm() {
  head_of "LiteLLM"
  row "Adresse:"  "$(addr litellm "${PORT_LITELLM:-4000}" /ui)"
  row "Benutzer:" "admin"
  row "Passwort:" "${LITELLM_MASTER_KEY:-<nicht gesetzt>}  (= Master-Key)"
  note "Fest vorgegeben — hier gibt es nichts anzulegen. Der Master-Key ist"
  note "zugleich der API-Schlüssel für Clients."
}

show_db() {
  head_of "PostgreSQL"
  row "Zugriff:"  "nur containerintern (kein Port veröffentlicht)"
  row "Benutzer:" "litellm"
  row "Passwort:" "${POSTGRES_PASSWORD:-<nicht gesetzt>}"
  note "psql:  docker exec -it litellm-db psql -U litellm"
}

show_mcp() {
  head_of "MCP Gateway"
  row "Adresse:"  "$(addr mcp "${PORT_MCP:-3000}")"
  row "Benutzer:" "admin  (Oberfläche MCPHub)"
  row "Passwort:" "steht in /var/lib/mcp/mcp_settings.json"
  row "API-Key:"  "${MCP_API_KEY:-<noch nicht verdrahtet — ./scripts/wire-mcp.sh>}"
  note "Passwort ansehen: docker exec mcp cat /var/lib/mcp/mcp_settings.json"
}

show_mcpo() {
  head_of "mcpo (Werkzeug-Übersicht)"
  row "Adresse:" "$(addr mcpo "${PORT_MCPO:-8800}" /mcp_gateway/docs)"
  warn "  Keine Anmeldung — wer den Port erreicht, kann alle Werkzeuge"
  warn "  aufrufen, inklusive Schreibzugriff auf den Vault."
  note "Deshalb gibt install.sh diesen Port immer nur fürs LAN frei."
}

show_syncthing() {
  head_of "Syncthing"
  row "Adresse:" "$(addr syncthing "${PORT_SYNCTHING_GUI:-8384}")"
  row "Benutzer:" "${SYNCTHING_GUI_USER:-admin}"
  pwrow "${SYNCTHING_GUI_PASSWORD:-}" SYNCTHING_GUI_PASSWORD_SET

  # Ob das Passwort WIRKLICH gilt, steht nicht in der .env, sondern in
  # Syncthings eigener Konfiguration — die .env hält nur den Wunschwert.
  # Ohne diese Prüfung würde hier "geschützt" stehen, während die Oberfläche
  # in Wahrheit offen ist.
  local applied="unbekannt"
  if running syncthing; then
    if docker exec syncthing sh -c 'grep -q "<password>[^<]" /var/syncthing/config/config.xml' 2>/dev/null; then
      applied="ja"
    else
      applied="nein"
    fi
  fi
  case "$applied" in
    ja)   note "In Syncthing hinterlegt (als Hash gespeichert)." ;;
    nein) warn "  NOCH NICHT gesetzt — die Oberfläche ist offen. Jeder im LAN"
          warn "  könnte deinen Vault umlenken."
          note "Setzen:  ./scripts/service-credentials.sh syncthing --create" ;;
    *)    note "Container läuft nicht — ob das Passwort gilt, ist von hier nicht prüfbar." ;;
  esac
}

show_dashboard()    { head_of "Dashboard";    row "Adresse:" "$(addr dashboard "${PORT_DASHBOARD:-8600}")";       note "Keine Anmeldung — nur im LAN erreichbar halten."; }
show_vault_bridge() { head_of "Vault-Bridge"; row "Adresse:" "$(addr vault-bridge "${PORT_VAULT_BRIDGE:-8700}")"; note "Keine Anmeldung; Nextcloud-Zugang wird in der Oberfläche selbst hinterlegt."; }
show_plain()        { head_of "$2";           row "Zugriff:" "nur containerintern, keine Anmeldung"; }

# ── Anlegen ─────────────────────────────────────────────────────────────────
create_librechat() { bash "$SCRIPT_DIR/librechat-user.sh"; }

create_open_webui() {
  local base url path body code
  running open-webui || { err "Container 'open-webui' läuft nicht."; return 1; }
  if [ -z "${OPENWEBUI_ADMIN_EMAIL:-}" ] || [ -z "${OPENWEBUI_ADMIN_PASSWORD:-}" ]; then
    err "OPENWEBUI_ADMIN_EMAIL/-PASSWORD fehlen in der .env."; return 1
  fi

  base="http://127.0.0.1:8080"
  # Den Registrierungs-Pfad NICHT raten: Open WebUI ändert seine Routen
  # zwischen Versionen. Stattdessen aus der OpenAPI-Beschreibung der laufenden
  # Instanz heraussuchen — was dort steht, gilt garantiert für DIESE Version.
  info "Suche den Registrierungs-Pfad in der OpenAPI-Beschreibung…"
  path="$(docker exec open-webui curl -sf --max-time 10 "$base/openapi.json" 2>/dev/null \
    | tr ',' '\n' | grep -oE '"/[a-zA-Z0-9/_.-]*signup"' | tr -d '"' | head -1)"
  if [ -z "$path" ]; then
    err "Kein Registrierungs-Pfad gefunden."
    info "Diese Open-WebUI-Version bietet keine Registrierung über die API"
    info "(oder sie ist abgeschaltet). Leg das Konto im Browser an:"
    info "  $(addr open-webui "${PORT_WEBUI:-3001}")"
    info "Der ERSTE dort registrierte Account wird automatisch Admin."
    info "Nimm die Zugangsdaten von oben, dann passen sie zur .env."
    return 1
  fi
  info "Gefunden: $path"

  body="$(printf '{"name":"%s","email":"%s","password":"%s"}' \
          "${OPENWEBUI_ADMIN_NAME:-Admin}" "$OPENWEBUI_ADMIN_EMAIL" "$OPENWEBUI_ADMIN_PASSWORD")"
  url="${base}${path}"
  code="$(docker exec open-webui curl -s -o /tmp/owui-signup.out -w '%{http_code}' \
          --max-time 20 -X POST "$url" -H 'Content-Type: application/json' -d "$body" 2>/dev/null)"
  case "$code" in
    2*) ok "Open-WebUI-Konto angelegt: $OPENWEBUI_ADMIN_EMAIL" ;;
    4*) warn "Abgelehnt (HTTP $code) — meist: Konto existiert schon oder Registrierung ist zu."
        docker exec open-webui sh -c 'head -c 300 /tmp/owui-signup.out' 2>/dev/null | sed 's/^/    /'; echo ;;
    *)  err "Unerwartete Antwort (HTTP ${code:-keine})." ;;
  esac
}

create_syncthing() {
  running syncthing || { err "Container 'syncthing' läuft nicht."; return 1; }
  local user="${SYNCTHING_GUI_USER:-admin}" pass="${SYNCTHING_GUI_PASSWORD:-}"
  [ -n "$pass" ] || { err "SYNCTHING_GUI_PASSWORD fehlt in der .env."; return 1; }

  # Passwort über die Standardeingabe, nicht als Argument: sonst stünde es in
  # der Prozessliste des Hosts. "-" ist dafür vorgesehen.
  info "Setze Benutzer und Passwort der Syncthing-Oberfläche…"
  if printf '%s' "$pass" | docker exec -i syncthing \
       syncthing generate --config=/var/syncthing/config \
       --gui-user="$user" --gui-password=- >/dev/null 2>&1; then
    ok "Gesetzt. Syncthing wird neu gestartet, damit es greift."
    if docker restart syncthing >/dev/null 2>&1; then
      ok "Syncthing neu gestartet."
    else
      warn "Neustart fehlgeschlagen — von Hand: docker restart syncthing"
    fi
  else
    err "syncthing generate ist fehlgeschlagen."
    info "Von Hand in der Oberfläche: Einstellungen → GUI → Benutzer/Passwort."
  fi
}

# ── Steuerung ───────────────────────────────────────────────────────────────
dispatch_show() {
  case "$1" in
    open-webui)   show_open_webui ;;
    librechat)    show_librechat ;;
    litellm)      show_litellm ;;
    db|postgres)  show_db ;;
    mcp)          show_mcp ;;
    mcpo)         show_mcpo ;;
    syncthing)    show_syncthing ;;
    dashboard)    show_dashboard ;;
    vault-bridge) show_vault_bridge ;;
    ollama)       show_plain "$1" "Ollama" ;;
    sandbox-mcp)  show_plain "$1" "Code-Sandbox" ;;
    android-mcp)  show_plain "$1" "Android-Build" ;;
    whisper)      show_plain "$1" "Whisper" ;;
    embeddings)   show_plain "$1" "Embeddings" ;;
    *) err "Unbekannter Dienst: $1"; return 1 ;;
  esac
}

if [ -n "$WANT" ]; then
  if [ "$CREATE" -eq 1 ]; then
    case "$WANT" in
      librechat)  create_librechat ;;
      open-webui) create_open_webui ;;
      syncthing)  create_syncthing ;;
      *) warn "Für '$WANT' gibt es kein Konto zum Anlegen."
         info "Anlegen möglich bei: librechat, open-webui, syncthing." ;;
    esac
    echo
  fi
  dispatch_show "$WANT" || exit 1
else
  printf '%s' "$c_bold"
  cat <<'BANNER'
╔══════════════════════════════════════════════════════╗
║   Self-Hosted AI Stack · Zugangsdaten aller Dienste  ║
╚══════════════════════════════════════════════════════╝
BANNER
  printf '%s' "$c_reset"
  for s in open-webui librechat litellm db mcp mcpo syncthing dashboard vault-bridge; do
    dispatch_show "$s"
  done
  printf '\n%s%sHinweis:%s Diese Werte stehen im Klartext in %s.env%s — nicht committen/teilen.\n' \
    "$c_blue" "$c_bold" "$c_reset$c_dim" "$c_bold" "$c_reset"
  printf '%sKonto anlegen:%s ./scripts/service-credentials.sh <dienst> --create\n' "$c_dim" "$c_reset"
  if [ -n "$NEWLY_ADDED" ]; then
    printf '\n%s%sIn die .env ergänzt:%s %s\n' "$c_yellow" "$c_bold" "$c_reset" "$NEWLY_ADDED"
    printf '%sDiese Werte gelten erst, wenn das jeweilige Konto damit angelegt wird.%s\n' "$c_dim" "$c_reset"
  fi
fi
