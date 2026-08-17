#!/usr/bin/env bash
#
# Self-Hosted AI Stack · Kontrollzentrum
#
# Ein Menü für den ganzen Stack: auswählen, was installiert/gestartet werden
# soll, auf einen Blick sehen, was bereits da ist, und alles wieder loswerden
# — bis hin zu Docker selbst.
#
# Die Kopfzeile bleibt dabei immer oben stehen: das Menü zeichnet den Bildschirm
# selbst (eigener Scroll-Offset für die Liste), und während ein Befehl läuft,
# wird die Scrollregion des Terminals (DECSTBM) auf den Bereich UNTER dem Kopf
# gesetzt — die Ausgabe scrollt dann nur dort, der Kopf steht fest.
#
# Aufruf:  ./stack-menu.sh          (oder: ./install.sh --menu)
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"
ENV_FILE="$ROOT_DIR/.env"
LOG_FILE="${TMPDIR:-/tmp}/stack-menu-$$.log"

# ── Terminal-Fähigkeiten ────────────────────────────────────────────────────
# Umlaute und Rahmenzeichen brauchen eine UTF-8-Locale; ohne sie zählt bash
# ${#s} Bytes statt Zeichen und die Spalten verrutschen. Wenn keine da ist,
# schalten wir auf reines ASCII um, statt kaputt zu zeichnen.
if ! locale charmap 2>/dev/null | grep -qi 'utf-\?8'; then
  for _l in C.UTF-8 en_US.UTF-8 de_DE.UTF-8; do
    if locale -a 2>/dev/null | grep -qix "${_l/UTF-8/utf8}\|$_l"; then export LC_ALL="$_l"; break; fi
  done
fi
if locale charmap 2>/dev/null | grep -qi 'utf-\?8'; then UNI=1; else UNI=0; fi

if [ "$UNI" -eq 1 ]; then
  G_RUN='●'; G_STOP='◍'; G_MISS='○'; G_WARN='▲'; G_SEL='❯'; G_ARROW='→'
  G_HL='─'; G_CUT='…'
else
  G_RUN='*'; G_STOP='o'; G_MISS='.'; G_WARN='!'; G_SEL='>'; G_ARROW='->'
  G_HL='-'; G_CUT='.'
fi

# ── Farben ──────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  c_reset=$'\033[0m';  c_bold=$'\033[1m';   c_dim=$'\033[2m'
  c_red=$'\033[38;5;204m';   c_green=$'\033[38;5;114m'
  c_yellow=$'\033[38;5;222m'; c_blue=$'\033[38;5;111m'
  c_mag=$'\033[38;5;176m';   c_cyan=$'\033[38;5;116m'
else
  c_reset=; c_bold=; c_dim=; c_red=; c_green=; c_yellow=; c_blue=; c_mag=; c_cyan=
fi

# ── Docker/Compose auflösen ─────────────────────────────────────────────────
SUDO=""
[ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

DC=""
resolve_dc() {
  if docker compose version >/dev/null 2>&1; then DC="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
  else DC=""; fi
}
command -v docker >/dev/null 2>&1 && resolve_dc

dc() {
  [ -n "$DC" ] || { echo "Docker Compose nicht gefunden."; return 1; }
  # shellcheck disable=SC2086
  (cd "$ROOT_DIR" && $DC -f "$COMPOSE_FILE" "$@")
}

# ════════════════════════════════════════════════════════════════════════════
# Einträge
# ════════════════════════════════════════════════════════════════════════════
# Format je Eintrag:  kind|id|label|desc|extra
#   kind=head : Überschrift (nicht anwählbar)
#   kind=svc  : Compose-Dienst; id=Dienst, extra=Containername[,Begleitdienste]
#   kind=sys  : Systemprüfung (docker, compose, gpu, ufw, env)
#   kind=cli  : Kommandozeilen-Werkzeug; da = Image gebaut, nicht dauerhaft laufend
#   kind=act  : Aktion (install, check, purge, …)
ITEMS=()
add() { ITEMS+=("$1|$2|$3|$4|${5:-}"); }

build_items() {
  ITEMS=()
  add head "" "Einrichtung" "" ""
  add act  install     "Stack installieren"        "install.sh — Hardware prüfen, .env anlegen, alles starten" ""
  add act  check       "Nur prüfen"                "install.sh --check-only — nichts verändern"                ""
  add act  credentials "Zugangsdaten anzeigen"     "URLs, Master-Key, Passwörter"                              ""

  add head "" "Kern" "" ""
  add svc  ollama    "Ollama"      "LLM-Engine (AMD ROCm)"                 "ollama"
  add svc  litellm   "LiteLLM"     "AI-Gateway, Schlüssel und Limits"      "litellm"
  add svc  db        "PostgreSQL"  "Datenbank mit pgvector"                "litellm-db"

  add head "" "Chat-Oberflächen" "" ""
  add svc  open-webui "Open WebUI" "Chat-Oberfläche (Werkzeuge über mcpo)" "open-webui"
  add svc  librechat  "LibreChat"  "Zweite Oberfläche, MCP nativ"          "librechat,librechat-mongo"

  add head "" "Werkzeuge fürs LLM" "" ""
  add svc  mcp         "MCP Gateway"   "Dateisystem, Web, Zeit, GitHub, DB" "mcp"
  add svc  mcpo        "mcpo"          "MCP -> OpenAPI für Open WebUI"      "mcpo"
  add svc  sandbox-mcp "Code-Sandbox"  "Code ausführen und testen"          "sandbox-mcp"
  add svc  android-mcp "Android-Build" "Gradle und Android SDK"             "android-mcp"

  add head "" "Wissensdatenbank" "" ""
  add svc  syncthing    "Syncthing"    "Vault zwischen deinen Geräten syncen" "syncthing"
  add svc  vault-bridge "Vault-Bridge" "Vault per Weboberfläche hochladen"    "vault-bridge"

  add head "" "Zusatzdienste" "" ""
  add svc  dashboard  "Dashboard"  "Status aller Dienste im Browser" "ai-stack-dashboard"
  add svc  whisper    "Whisper"    "Sprache zu Text"                 "whisper"
  add svc  embeddings "Embeddings" "Text zu Vektoren"                "embeddings"

  add head "" "CLI-Werkzeuge" "" ""
  add cli  interpreter "Open Interpreter" "Assistent für die Kommandozeile, führt Code aus" ""

  add head "" "System" "" ""
  add sys  docker  "Docker"          "Container-Laufzeit"           ""
  add sys  compose "Docker Compose"  "Orchestrierung des Stacks"    ""
  add sys  gpu     "GPU / ROCm"      "AMD-Beschleunigung für Ollama" ""
  add sys  ufw     "Firewall (ufw)"  "Ports nur fürs LAN freigeben"  ""
  add sys  env     ".env"            "Ports, Schlüssel, Passwörter"  ""

  add head "" "Aufräumen und entfernen" "" ""
  add act  stopall   "Alles stoppen"           "Container anhalten, Daten bleiben"           ""
  add act  restart   "Alles neu starten"       "Stack durchstarten"                          ""
  add act  restmcp   "MCP-Dienste neu starten" "restart-mcp.sh — in der richtigen Reihenfolge" ""
  add act  prune     "Ungenutztes aufräumen"   "Verwaiste Images und Build-Cache löschen"    ""
  add act  uninstall "Stack entfernen"         "Container weg, Daten-Volumes bleiben"        ""
  add act  purge     "Stack + alle Daten löschen" "Modelle, Chats, Datenbank, .env — endgültig" ""
  add act  rmdocker  "Docker deinstallieren"   "Docker-Pakete vom System entfernen"          ""
}

# ════════════════════════════════════════════════════════════════════════════
# Zustand einlesen
# ════════════════════════════════════════════════════════════════════════════
ST_RUNNING=" "; ST_EXISTING=" "; ST_UNHEALTHY=" "
HAS_DOCKER=0; DOCKER_UP=0

refresh_state() {
  HAS_DOCKER=0; DOCKER_UP=0
  ST_RUNNING=" "; ST_EXISTING=" "; ST_UNHEALTHY=" "
  command -v docker >/dev/null 2>&1 && HAS_DOCKER=1
  [ -z "$DC" ] && command -v docker >/dev/null 2>&1 && resolve_dc
  if [ "$HAS_DOCKER" -eq 1 ] && docker info >/dev/null 2>&1; then
    DOCKER_UP=1
    ST_RUNNING=" $(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
    ST_EXISTING=" $(docker ps -a --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
    ST_UNHEALTHY=" $(docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
  fi
}

# Ist "$1" in der Liste "$2" (Liste ist leerzeichengerahmt)?
in_list() { case "$2" in *" $1 "*) return 0 ;; esac; return 1; }

# Status eines Compose-Dienstes: run | unhealthy | stopped | missing
svc_state() {
  local containers="$1" c any_run=0 any_exist=0 any_unhealthy=0 all_run=1
  local IFS=','
  for c in $containers; do
    if in_list "$c" "$ST_UNHEALTHY"; then any_unhealthy=1; fi
    if in_list "$c" "$ST_RUNNING"; then any_run=1; else all_run=0; fi
    if in_list "$c" "$ST_EXISTING"; then any_exist=1; fi
  done
  if [ "$any_unhealthy" -eq 1 ]; then echo unhealthy
  elif [ "$any_run" -eq 1 ] && [ "$all_run" -eq 1 ]; then echo run
  elif [ "$any_run" -eq 1 ]; then echo partial
  elif [ "$any_exist" -eq 1 ]; then echo stopped
  else echo missing; fi
}

sys_state() {
  case "$1" in
    docker)
      [ "$HAS_DOCKER" -eq 1 ] || { echo missing; return; }
      [ "$DOCKER_UP" -eq 1 ] && echo run || echo stopped ;;
    compose) [ -n "$DC" ] && echo run || echo missing ;;
    gpu)
      if [ -e /dev/kfd ] && [ -e /dev/dri ]; then echo run
      elif [ -e /dev/dri ]; then echo partial
      else echo missing; fi ;;
    ufw)
      command -v ufw >/dev/null 2>&1 || { echo missing; return; }
      if $SUDO ufw status 2>/dev/null | head -1 | grep -qi 'active'; then echo run; else echo stopped; fi ;;
    env) [ -f "$ENV_FILE" ] && echo run || echo missing ;;
  esac
}

# CLI-Werkzeuge sind keine Dienste — sie "laufen" nicht, sie sind gebaut oder
# nicht. Compose benennt lokal gebaute Images "<projekt>-<dienst>"; der
# Projektname ist der Ordnername in Kleinbuchstaben.
cli_state() {
  local svc="$1" proj
  [ "$DOCKER_UP" -eq 1 ] || { echo missing; return; }
  proj="$(basename "$ROOT_DIR" | tr '[:upper:]' '[:lower:]')"
  if docker image inspect "${proj}-${svc}" >/dev/null 2>&1 \
     || docker image inspect "${proj}_${svc}" >/dev/null 2>&1; then
    echo run
  else
    echo missing
  fi
}

act_state() {
  case "$1" in
    install)     [ -f "$ENV_FILE" ] && echo run || echo missing ;;
    credentials) [ -f "$ENV_FILE" ] && echo none || echo missing ;;
    check)       echo none ;;
    restmcp)     if [ -f "$ROOT_DIR/scripts/restart-mcp.sh" ]; then echo none; else echo missing; fi ;;
    *)           echo none ;;
  esac
}

# Anzeige zu einem Status: Symbol + Text + Farbe.
# $1 = Status, $2 = Art des Eintrags — ein Systemwerkzeug "läuft" nicht,
# es ist vorhanden; eine Aktion ist erledigt oder offen.
state_badge() {
  case "$1" in
    run)       BADGE_SYM="$G_RUN";  BADGE_COL="$c_green"  ;;
    partial)   BADGE_SYM="$G_WARN"; BADGE_COL="$c_yellow" ;;
    unhealthy) BADGE_SYM="$G_WARN"; BADGE_COL="$c_red"    ;;
    stopped)   BADGE_SYM="$G_STOP"; BADGE_COL="$c_yellow" ;;
    missing)   BADGE_SYM="$G_MISS"; BADGE_COL="$c_dim"    ;;
    *)         BADGE_SYM=" ";       BADGE_COL="$c_dim"    ;;
  esac
  case "$2:$1" in
    svc:run)       BADGE_TXT="läuft" ;;
    svc:partial)   BADGE_TXT="teilweise" ;;
    svc:unhealthy) BADGE_TXT="ungesund" ;;
    svc:stopped)   BADGE_TXT="gestoppt" ;;
    svc:missing)   BADGE_TXT="nicht da" ;;
    sys:run)       BADGE_TXT="bereit" ;;
    sys:partial)   BADGE_TXT="teilweise" ;;
    sys:stopped)   BADGE_TXT="aus" ;;
    sys:missing)   BADGE_TXT="fehlt" ;;
    cli:run)       BADGE_TXT="installiert" ;;
    cli:missing)   BADGE_TXT="nicht da" ;;
    act:run)       BADGE_TXT="erledigt" ;;
    act:missing)   BADGE_TXT="offen" ;;
    *)             BADGE_TXT="" ;;
  esac
}

item_state() {
  local kind="$1" id="$2" extra="$3"
  case "$kind" in
    svc) [ "$DOCKER_UP" -eq 1 ] && svc_state "$extra" || echo missing ;;
    cli) cli_state "$id" ;;
    sys) sys_state "$id" ;;
    act) act_state "$id" ;;
    *)   echo none ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# Zeichnen
# ════════════════════════════════════════════════════════════════════════════
# Waagerechte Linie der Breite $1. Bewusst ohne 'tr': tr arbeitet bytewise und
# würde das mehrbyte '─' in Einzelbytes zerhacken.
hr() {
  local n="$1" s
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$G_HL}"
}

# Zeichenweise lesen, ohne Echo — aber bewusst NICHT über "stty raw":
# raw schaltet zusätzlich die AUSGABE-Verarbeitung ab (ONLCR). Dann ist "\n"
# nur noch ein Zeilenvorschub ohne Wagenrücklauf, jede Zeile beginnt dort, wo
# die vorige endete, und das Bild läuft treppenförmig nach rechts aus dem
# Terminal. -icanon -echo gibt uns die Einzelzeichen, ohne das anzurühren.
term_read_mode() { stty -icanon -echo min 1 time 0 2>/dev/null || true; }

ROWS=24; COLS=80
measure() {
  ROWS=$(tput lines 2>/dev/null || echo 24)
  COLS=$(tput cols  2>/dev/null || echo 80)
  [ "$ROWS" -lt 12 ] && ROWS=12
  [ "$COLS" -lt 50 ] && COLS=50
}

# Auf $2 Zeichen kürzen/auffüllen — zeichen-, nicht bytebasiert (UTF-8-Locale
# ist oben gesetzt), damit Umlaute die Spalten nicht verschieben.
fit() {
  local s="$1" w="$2"
  if [ "${#s}" -gt "$w" ]; then printf '%s%s' "${s:0:$((w-1))}" "$G_CUT"
  else printf '%s%*s' "$s" "$((w - ${#s}))" ""; fi
}

# Eigenes Logo: ein Chip mit Pins — steht für "läuft auf eigener Hardware".
# Chip und Schriftzug getrennt, damit die Spalten unabhängig von der Farbe
# stimmen. LOGO_LINES muss zur Zeilenzahl von CHIP passen.
if [ "$UNI" -eq 1 ]; then
  CHIP=(
    '      ┌─┬─┬─┬─┐      '
    '  ┌───┴─┴─┴─┴───┐    '
    '  │  ▄▄     ▄▄  │    '
    '──┤  ██  ▄  ██  ├──  '
    '  │  ▀▀  █  ▀▀  │    '
    '  └───┬─┬─┬─┬───┘    '
    '      └─┴─┴─┴─┘      '
  )
else
  CHIP=(
    '      +-+-+-+-+      '
    '  +---+-+-+-+---+    '
    '  |  ##     ##  |    '
    '--+  ##  #  ##  +--  '
    '  |  ##  #  ##  |    '
    '  +---+-+-+-+---+    '
    '      +-+-+-+-+      '
  )
fi
WORD=( '' '' 'SELF-HOSTED' 'A I   S T A C K' '' '' '' )
WORDCOL=( '' '' "$c_bold$c_blue" "$c_bold$c_green" '' '' '' )
LOGO_LINES=${#CHIP[@]}
# Kopf = Logo + Zusammenfassungszeile + Trennlinie
HEADER_LINES=$((LOGO_LINES + 2))

draw_logo() {
  local i=0
  while [ "$i" -lt "$LOGO_LINES" ]; do
    printf '  %s%s%s  %s%s%s\n' \
      "$c_cyan" "${CHIP[$i]}" "$c_reset" \
      "${WORDCOL[$i]}" "${WORD[$i]}" "$c_reset"
    i=$((i+1))
  done
}

draw_header() {
  local inner=$((COLS - 2))
  draw_logo
  # Zusammenfassung: wie viele Dienste laufen, wie viele fehlen
  local total=0 running=0 missing=0 line kind id extra st
  for line in "${ITEMS[@]}"; do
    IFS='|' read -r kind id _ _ extra <<<"$line"
    [ "$kind" = "svc" ] || continue
    total=$((total+1))
    st=$(item_state "$kind" "$id" "$extra")
    case "$st" in run) running=$((running+1)) ;; missing) missing=$((missing+1)) ;; esac
  done
  local dockertxt
  if [ "$DOCKER_UP" -eq 1 ]; then dockertxt="${c_green}${G_RUN} Docker${c_reset}"
  elif [ "$HAS_DOCKER" -eq 1 ]; then dockertxt="${c_red}${G_WARN} Docker aus${c_reset}"
  else dockertxt="${c_dim}${G_MISS} kein Docker${c_reset}"; fi
  # Auf schmalen Terminals fällt zuerst der Dateiname weg, dann die Langform.
  # Gemessen wird an der FARBLOSEN Fassung — Escape-Sequenzen belegen keine
  # Spalten, würden hier aber mitgezählt und die Zeile grundlos kürzen.
  local dockerplain
  if [ "$DOCKER_UP" -eq 1 ]; then dockerplain="${G_RUN} Docker"
  elif [ "$HAS_DOCKER" -eq 1 ]; then dockerplain="${G_WARN} Docker aus"
  else dockerplain="${G_MISS} kein Docker"; fi

  local stats_long="Dienste: ${running} läuft · ${missing} fehlt · ${total} gesamt"
  local plain

  plain="  ${COMPOSE_FILE}  ${dockerplain}  ${stats_long}"
  if [ "${#plain}" -le "$COLS" ]; then
    printf '  %s%s%s  %s  %sDienste:%s %s%d läuft%s · %s%d fehlt%s · %d gesamt\n' \
      "$c_dim" "$COMPOSE_FILE" "$c_reset" "$dockertxt" \
      "$c_dim" "$c_reset" "$c_green" "$running" "$c_reset" "$c_dim" "$missing" "$c_reset" "$total"
  else
    plain="  ${dockerplain}  ${stats_long}"
    if [ "${#plain}" -le "$COLS" ]; then
      printf '  %s  %sDienste:%s %s%d läuft%s · %s%d fehlt%s · %d gesamt\n' \
        "$dockertxt" "$c_dim" "$c_reset" "$c_green" "$running" "$c_reset" \
        "$c_dim" "$missing" "$c_reset" "$total"
    else
      printf '  %s  %s%d/%d läuft%s · %s%d fehlt%s\n' \
        "$dockertxt" "$c_green" "$running" "$total" "$c_reset" "$c_dim" "$missing" "$c_reset"
    fi
  fi
  printf '  %s%s%s\n' "$c_dim" "$(hr "$inner")" "$c_reset"
}

SEL=0        # Index in ITEMS
TOP=0        # erster sichtbarer Listeneintrag
VIEW=10      # sichtbare Zeilen der Liste

draw_list() {
  local i=0 line kind id label desc extra st shown=0
  local labw=22 statw=12
  local descw=$((COLS - labw - statw - 8))
  [ "$descw" -lt 10 ] && descw=10
  for line in "${ITEMS[@]}"; do
    if [ "$i" -lt "$TOP" ]; then i=$((i+1)); continue; fi
    [ "$shown" -ge "$VIEW" ] && break
    IFS='|' read -r kind id label desc extra <<<"$line"
    if [ "$kind" = "head" ]; then
      printf '  %s%s%s%s\n' "$c_bold" "$c_blue" "$label" "$c_reset"
    else
      st=$(item_state "$kind" "$id" "$extra"); state_badge "$st" "$kind"
      local mark="  " lab
      lab="$(fit "$label" "$labw")"
      if [ "$i" -eq "$SEL" ]; then
        mark="${c_bold}${c_mag}${G_SEL} ${c_reset}"
        lab="${c_bold}${lab}${c_reset}"
      fi
      printf '  %s%s %s%s %s%s%s  %s%s%s\n' \
        "$mark" "$lab" \
        "$BADGE_COL" "$BADGE_SYM" "$BADGE_COL" "$(fit "$BADGE_TXT" $((statw-2)))" "$c_reset" \
        "$c_dim" "$(fit "$desc" "$descw")" "$c_reset"
    fi
    shown=$((shown+1)); i=$((i+1))
  done
  while [ "$shown" -lt "$VIEW" ]; do printf '\n'; shown=$((shown+1)); done
}

draw_footer() {
  local inner=$((COLS - 2))
  printf '  %s%s%s\n' "$c_dim" "$(hr "$inner")" "$c_reset"
  local more=""
  [ "$((TOP + VIEW))" -lt "${#ITEMS[@]}" ] && more="${c_yellow}↓ mehr${c_reset}  "
  [ "$TOP" -gt 0 ] && more="${c_yellow}↑ mehr${c_reset}  $more"
  # Dieselbe Logik wie oben: lieber weniger Hinweise als eine umbrechende Zeile.
  local moreplain=""
  [ "$((TOP + VIEW))" -lt "${#ITEMS[@]}" ] && moreplain="↓ mehr  "
  [ "$TOP" -gt 0 ] && moreplain="↑ mehr  $moreplain"
  local keys_long="  ${moreplain}↑↓ wählen  Enter öffnen  s starten  x stoppen  l Logs  r neu prüfen  q Ende"
  if [ "${#keys_long}" -le "$COLS" ]; then
    printf '  %s%s↑↓%s wählen  %sEnter%s öffnen  %ss%s starten  %sx%s stoppen  %sl%s Logs  %sr%s neu prüfen  %sq%s Ende\n' \
      "$more" "$c_bold" "$c_reset" "$c_bold" "$c_reset" "$c_bold" "$c_reset" \
      "$c_bold" "$c_reset" "$c_bold" "$c_reset" "$c_bold" "$c_reset" "$c_bold" "$c_reset"
  else
    printf '  %s%s↑↓%s wählen  %sEnter%s öffnen  %sr%s neu  %sq%s Ende\n' \
      "$more" "$c_bold" "$c_reset" "$c_bold" "$c_reset" "$c_bold" "$c_reset" "$c_bold" "$c_reset"
  fi
}

draw() {
  measure
  VIEW=$((ROWS - HEADER_LINES - 3))
  [ "$VIEW" -lt 3 ] && VIEW=3
  # Auswahl im sichtbaren Bereich halten
  [ "$SEL" -lt "$TOP" ] && TOP="$SEL"
  [ "$SEL" -ge "$((TOP + VIEW))" ] && TOP=$((SEL - VIEW + 1))
  [ "$TOP" -lt 0 ] && TOP=0
  # Ganzen Frame auf einmal ausgeben (weniger Flackern)
  { printf '\033[H\033[2J'; draw_header; draw_list; draw_footer; } 2>/dev/null
}

# ── Navigation ──────────────────────────────────────────────────────────────
selectable() {
  local line kind
  line="${ITEMS[$1]}"; IFS='|' read -r kind _ _ _ _ <<<"$line"
  [ "$kind" != "head" ]
}
move() {
  local dir="$1" n="${#ITEMS[@]}" i="$SEL"
  while :; do
    i=$((i + dir))
    [ "$i" -lt 0 ] && return
    [ "$i" -ge "$n" ] && return
    if selectable "$i"; then SEL="$i"; return; fi
  done
}
first_selectable() {
  local i=0
  while [ "$i" -lt "${#ITEMS[@]}" ]; do selectable "$i" && { SEL="$i"; return; }; i=$((i+1)); done
}

# ════════════════════════════════════════════════════════════════════════════
# Befehle ausführen — Kopf bleibt oben, Ausgabe scrollt darunter
# ════════════════════════════════════════════════════════════════════════════
# Wir setzen die Scrollregion des Terminals (DECSTBM) auf die Zeilen unterhalb
# des Kopfes. Alles, was der Befehl ausgibt, scrollt dann nur in diesem
# Fenster; die Kopfzeile darüber bleibt unberührt stehen.
run_cmd() {
  local title="$1"; shift
  measure
  local top=$((HEADER_LINES + 2))   # erste Zeile unter Kopf + Titelzeile
  local bottom=$((ROWS - 2))
  [ "$bottom" -le "$top" ] && bottom=$((top + 1))

  printf '\033[H\033[2J'
  draw_header
  printf '  %s%s%s\n' "$c_bold" "$title" "$c_reset"
  printf '\033[%d;%dr' "$top" "$bottom"   # Scrollregion setzen
  printf '\033[%d;1H' "$top"              # Cursor in die Region
  printf '\033[?25h'                      # Cursor sichtbar (Befehle fragen ggf.)
  stty "$STTY_SAVE" 2>/dev/null || true   # normales Terminal für den Befehl

  # Strg-C soll nur den laufenden Befehl treffen, nicht das Menü beenden.
  trap '' INT
  local rc=0
  "$@" 2>&1 | tee "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  trap 'exit 130' INT

  printf '\033[r'                         # Scrollregion zurücksetzen
  # Beide Zeilen vor dem Schreiben leeren (\033[2K) — sonst bleiben Reste der
  # Befehlsausgabe stehen, die bis an den Rand der Region gescrollt ist.
  printf '\033[%d;1H\033[2K' "$((ROWS - 1))"
  if [ "$rc" -eq 0 ]; then
    printf '  %s%s fertig%s' "$c_green" "$G_RUN" "$c_reset"
  else
    printf '  %s%s fehlgeschlagen (Code %s)%s' "$c_red" "$G_WARN" "$rc" "$c_reset"
  fi
  printf '   %sProtokoll: %s%s' "$c_dim" "$LOG_FILE" "$c_reset"
  printf '\033[%d;1H\033[2K' "$ROWS"
  printf '  %sWeiter mit Enter …%s' "$c_dim" "$c_reset"
  term_read_mode
  read -r -n 1 _ >/dev/null 2>&1
  printf '\033[?25l'
  refresh_state
  return "$rc"
}

# Ja/Nein-Abfrage in der letzten Zeile
confirm() {
  local q="$1" ans
  measure
  printf '\033[%d;1H\033[2K  %s%s%s [j/N] ' "$ROWS" "$c_yellow" "$q" "$c_reset"
  printf '\033[?25h'
  stty "$STTY_SAVE" 2>/dev/null || true
  read -r ans || ans=""
  term_read_mode
  printf '\033[?25l'
  case "$ans" in [jJyY]*) return 0 ;; *) return 1 ;; esac
}

# Abfrage, bei der ein Wort exakt getippt werden muss (für Destruktives)
confirm_word() {
  local q="$1" word="$2" ans
  measure
  printf '\033[%d;1H\033[2K  %s%s Tippe »%s«: %s' "$ROWS" "$c_red" "$q" "$word" "$c_reset"
  printf '\033[?25h'
  stty "$STTY_SAVE" 2>/dev/null || true
  read -r ans || ans=""
  term_read_mode
  printf '\033[?25l'
  [ "$ans" = "$word" ]
}

# ── Aktionen ────────────────────────────────────────────────────────────────
svc_up()      { run_cmd "Starte $1 …"     bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' up -d ${1//,/ }"; }
svc_build()   { run_cmd "Baue $1 neu …"   bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' up -d --build ${1//,/ }"; }
svc_stop()    { run_cmd "Stoppe $1 …"     bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' stop ${1//,/ }"; }
svc_restart() { run_cmd "Starte $1 neu …" bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' restart ${1//,/ }"; }
svc_rm()      { run_cmd "Entferne $1 …"   bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' rm -sf ${1//,/ }"; }
svc_logs()    { run_cmd "Logs: $1 (letzte 200 Zeilen)" bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' logs --tail 200 --no-color ${1//,/ }"; }

remove_docker() {
  local pkg=""
  command -v apt-get >/dev/null 2>&1 && pkg=apt
  command -v dnf     >/dev/null 2>&1 && pkg=dnf
  command -v pacman  >/dev/null 2>&1 && pkg=pacman
  if [ -z "$pkg" ]; then
    run_cmd "Docker deinstallieren" bash -c \
      'echo "Kein bekannter Paketmanager (apt/dnf/pacman) — bitte manuell entfernen."; exit 1'
    return
  fi
  local script
  case "$pkg" in
    apt)    script="$SUDO apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-compose || true; $SUDO apt-get autoremove -y || true" ;;
    dnf)    script="$SUDO dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true" ;;
    pacman) script="$SUDO pacman -Rns --noconfirm docker docker-compose || true" ;;
  esac
  if confirm_word "Docker wird vom System entfernt. Das trifft ALLE Container, nicht nur diesen Stack." "docker weg"; then
    run_cmd "Deinstalliere Docker ($pkg) …" bash -c "$script"
    if confirm "Auch /var/lib/docker löschen (alle Images, Volumes, Container — endgültig)?"; then
      run_cmd "Lösche /var/lib/docker …" bash -c "$SUDO rm -rf /var/lib/docker /var/lib/containerd && echo 'Gelöscht.'"
    fi
  fi
}

# Aktionsmenü zu einem Eintrag: Zeilen einsammeln, auswählen lassen
# MENU_KEYS/MENU_LABELS werden von menu_pick() genutzt.
MENU_KEYS=(); MENU_LABELS=()
mitem() { MENU_KEYS+=("$1"); MENU_LABELS+=("$2"); }

menu_pick() {
  local title="$1" sel=0 n="${#MENU_KEYS[@]}" key rest
  [ "$n" -eq 0 ] && { PICKED=""; return 1; }
  while :; do
    measure
    printf '\033[H\033[2J'; draw_header
    printf '  %s%s%s\n\n' "$c_bold" "$title" "$c_reset"
    local i=0
    while [ "$i" -lt "$n" ]; do
      if [ "$i" -eq "$sel" ]; then
        printf '   %s%s%s %s%s\n' "$c_mag" "$G_SEL" "$c_bold" "${MENU_LABELS[$i]}" "$c_reset"
      else
        printf '     %s\n' "${MENU_LABELS[$i]}"
      fi
      i=$((i+1))
    done
    printf '\n  %s↑↓ wählen · Enter bestätigen · Esc/q zurück%s' "$c_dim" "$c_reset"

    IFS= read -rsn1 key || key=""
    case "$key" in
      $'\033')
        read -rsn2 -t 0.05 rest || rest=""
        case "$rest" in
          '[A') [ "$sel" -gt 0 ] && sel=$((sel-1)) ;;
          '[B') [ "$sel" -lt "$((n-1))" ] && sel=$((sel+1)) ;;
          '')   PICKED=""; return 1 ;;
        esac ;;
      k) [ "$sel" -gt 0 ] && sel=$((sel-1)) ;;
      j) [ "$sel" -lt "$((n-1))" ] && sel=$((sel+1)) ;;
      q) PICKED=""; return 1 ;;
      ''|$'\r'|$'\n') PICKED="${MENU_KEYS[$sel]}"; return 0 ;;
    esac
  done
}

open_item() {
  local line kind id label desc extra st
  line="${ITEMS[$SEL]}"; IFS='|' read -r kind id label desc extra <<<"$line"
  st=$(item_state "$kind" "$id" "$extra")

  MENU_KEYS=(); MENU_LABELS=()
  case "$kind" in
    svc)
      if [ "$st" = "missing" ] || [ "$st" = "stopped" ]; then
        mitem up "Starten / installieren"
      else
        mitem restart "Neu starten"
        mitem stop    "Stoppen"
      fi
      mitem logs  "Logs ansehen"
      mitem build "Neu bauen und starten"
      mitem rm    "Container entfernen (Daten bleiben)"
      menu_pick "$label $G_ARROW was tun?" || return
      case "$PICKED" in
        up) svc_up "$id" ;; restart) svc_restart "$id" ;; stop) svc_stop "$id" ;;
        logs) svc_logs "$id" ;; build) svc_build "$id" ;;
        rm) confirm "$label entfernen? Daten-Volumes bleiben erhalten." && svc_rm "$id" ;;
      esac ;;
    cli)
      case "$id" in
        interpreter)
          if [ "$st" = "run" ]; then
            mitem start "Starten"
            mitem yolo  "Starten, ohne bei jedem Schritt zu fragen"
          else
            mitem build "Installieren (Image bauen)"
          fi
          mitem build2 "Image neu bauen"
          mitem rm     "Entfernen (Image löschen)"
          menu_pick "Open Interpreter $G_ARROW was tun?" || return
          case "$PICKED" in
            start)  run_cmd "Open Interpreter" bash -c "cd '$ROOT_DIR' && bash scripts/interpreter.sh" ;;
            yolo)   confirm "Ohne Rückfrage heißt: das Modell führt Code direkt aus (im Container, nur /work)." \
                      && run_cmd "Open Interpreter (-y)" bash -c "cd '$ROOT_DIR' && bash scripts/interpreter.sh -y" ;;
            build|build2) run_cmd "Baue Open Interpreter" bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' --profile cli build interpreter" ;;
            rm)     confirm "Image löschen? Der Arbeitsbereich /work bleibt erhalten." \
                      && run_cmd "Entferne Open Interpreter" bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' --profile cli down --rmi local interpreter 2>/dev/null; docker image rm \"\$(basename '$ROOT_DIR' | tr '[:upper:]' '[:lower:]')-interpreter\" 2>&1 || true" ;;
          esac ;;
      esac ;;
    sys)
      case "$id" in
        docker)
          mitem info "Version und Status anzeigen"
          mitem inst "Docker installieren (über install.sh)"
          mitem rm   "Docker deinstallieren"
          menu_pick "Docker $G_ARROW was tun?" || return
          case "$PICKED" in
            info) run_cmd "Docker-Status" bash -c 'docker version; echo; docker info | head -30' ;;
            inst) run_cmd "install.sh" bash -c "cd '$ROOT_DIR' && $SUDO ./install.sh" ;;
            rm)   remove_docker ;;
          esac ;;
        compose)
          run_cmd "Compose-Version" bash -c "cd '$ROOT_DIR' && $DC version" ;;
        gpu)
          mitem info "GPU-Geräte anzeigen"
          mitem test "ROCm im Ollama-Container prüfen"
          menu_pick "GPU / ROCm $G_ARROW was tun?" || return
          case "$PICKED" in
            info) run_cmd "GPU-Geräte" bash -c 'ls -l /dev/kfd /dev/dri 2>&1; echo; (lspci | grep -i vga) 2>/dev/null || true' ;;
            test) run_cmd "ROCm im Container" bash -c 'docker exec ollama rocminfo 2>&1 | head -30 || echo "Container ollama läuft nicht."' ;;
          esac ;;
        ufw)
          mitem status "Regeln anzeigen"
          mitem lan    "Ports nur fürs LAN freigeben (startet install.sh neu)"
          mitem open   "Ports für alle öffnen (nur mit HTTPS davor!)"
          mitem off    "Firewall ausschalten"
          menu_pick "Firewall $G_ARROW was tun?" || return
          case "$PICKED" in
            status) run_cmd "Firewall-Regeln" bash -c "$SUDO ufw status numbered" ;;
            lan)    run_cmd "Firewall: nur LAN" bash -c "cd '$ROOT_DIR' && $SUDO ./install.sh --firewall=lan" ;;
            open)   confirm "Ports für ALLE öffnen? Nur sinnvoll mit Reverse-Proxy und HTTPS davor." \
                      && run_cmd "Firewall: offen" bash -c "cd '$ROOT_DIR' && $SUDO ./install.sh --firewall=open" ;;
            off)    confirm "Firewall wirklich ausschalten?" && run_cmd "Firewall aus" bash -c "$SUDO ufw disable" ;;
          esac ;;
        env)
          mitem show "Werte anzeigen (Schlüssel maskiert)"
          mitem edit "Bearbeiten (\$EDITOR)"
          menu_pick ".env $G_ARROW was tun?" || return
          case "$PICKED" in
            show) run_cmd ".env" bash -c "sed -E 's/(KEY|PASSWORD|SECRET|TOKEN)=.*/\\1=********/' '$ENV_FILE'" ;;
            edit) run_cmd "Bearbeiten" bash -c "\${EDITOR:-nano} '$ENV_FILE'" ;;
          esac ;;
      esac ;;
    act)
      case "$id" in
        install)     run_cmd "install.sh"        bash -c "cd '$ROOT_DIR' && $SUDO ./install.sh" ;;
        check)       run_cmd "install.sh --check-only" bash -c "cd '$ROOT_DIR' && ./install.sh --check-only" ;;
        credentials) run_cmd "Zugangsdaten"      bash -c "cd '$ROOT_DIR' && ./scripts/show-credentials.sh" ;;
        stopall)     confirm "Alle Dienste stoppen?" && run_cmd "Stoppe alles" bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' stop" ;;
        restart)     run_cmd "Starte alles neu"  bash -c "cd '$ROOT_DIR' && $DC -f '$COMPOSE_FILE' up -d" ;;
        restmcp)     run_cmd "MCP-Dienste neu starten" bash -c "cd '$ROOT_DIR' && bash scripts/restart-mcp.sh" ;;
        prune)       confirm "Ungenutzte Images und Build-Cache löschen?" && run_cmd "Räume auf" bash -c "docker system prune -f" ;;
        uninstall)   confirm "Stack entfernen? Container weg, Daten-Volumes bleiben." \
                       && run_cmd "Entferne Stack" bash -c "cd '$ROOT_DIR' && $SUDO ./install.sh --uninstall" ;;
        purge)       confirm_word "Das löscht Modelle, Chats, Datenbank und .env — endgültig." "loeschen" \
                       && run_cmd "Lösche alles" bash -c "cd '$ROOT_DIR' && $SUDO ./install.sh --purge --yes" ;;
        rmdocker)    remove_docker ;;
      esac ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# Hauptschleife
# ════════════════════════════════════════════════════════════════════════════
STTY_SAVE=""
cleanup() {
  printf '\033[r'          # Scrollregion zurücksetzen
  printf '\033[?25h'       # Cursor an
  if [ -n "$STTY_SAVE" ]; then stty "$STTY_SAVE" 2>/dev/null || true; fi
  tput rmcup 2>/dev/null || printf '\033[?1049l'
  rm -f "$LOG_FILE"
}

main() {
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "stack-menu.sh braucht ein interaktives Terminal." >&2
    echo "Ohne Menü: ./install.sh, ./stack-check.sh, ./scripts/show-credentials.sh" >&2
    exit 1
  fi
  [ -f "$ROOT_DIR/$COMPOSE_FILE" ] || {
    echo "Compose-Datei nicht gefunden: $ROOT_DIR/$COMPOSE_FILE" >&2; exit 1; }

  STTY_SAVE="$(stty -g 2>/dev/null || true)"
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  trap 'measure' WINCH
  tput smcup 2>/dev/null || printf '\033[?1049h'
  printf '\033[?25l'
  term_read_mode

  build_items
  refresh_state
  first_selectable

  local key rest
  while :; do
    draw
    IFS= read -rsn1 key || key=""
    case "$key" in
      $'\033')
        read -rsn2 -t 0.05 rest || rest=""
        case "$rest" in
          '[A') move -1 ;;
          '[B') move  1 ;;
          '[5') read -rsn1 -t 0.05 _ || true; local n=0; while [ "$n" -lt 5 ]; do move -1; n=$((n+1)); done ;;
          '[6') read -rsn1 -t 0.05 _ || true; local n=0; while [ "$n" -lt 5 ]; do move  1; n=$((n+1)); done ;;
          '[H') first_selectable ;;
        esac ;;
      k) move -1 ;;
      j) move  1 ;;
      ''|$'\r'|$'\n') open_item ;;                  # Enter (je nach Terminal CR/LF)
      s) svc_shortcut up ;;
      x) svc_shortcut stop ;;
      l) svc_shortcut logs ;;
      r) refresh_state ;;
      q) break ;;
    esac
  done
}

# Direkt-Tasten (s/x/l) — nur sinnvoll auf Dienst-Einträgen
svc_shortcut() {
  local line kind id
  line="${ITEMS[$SEL]}"; IFS='|' read -r kind id _ _ _ <<<"$line"
  [ "$kind" = "svc" ] || return 0
  case "$1" in
    up)   svc_up   "$id" ;;
    stop) svc_stop "$id" ;;
    logs) svc_logs "$id" ;;
  esac
}

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Self-Hosted AI Stack · Kontrollzentrum

  ./stack-menu.sh          Menü öffnen
  ./install.sh --menu      dasselbe

Tasten
  ↑ ↓ / k j     Eintrag wählen        Enter   Aktionen zum Eintrag öffnen
  s             starten                x      stoppen
  l             Logs                   r      Status neu einlesen
  q             beenden

Umgebung
  COMPOSE_FILE  Compose-Datei (Standard: docker-compose.rocm.yml)
  NO_COLOR      Farben aus
EOF
    exit 0 ;;
esac

main "$@"
