#!/usr/bin/env bash
#
# Prüft, warum LibreChat (oder Open WebUI) keine MCP-Werkzeuge sieht.
#
# Geht die Kette von hinten durch: laufen die MCP-Dienste, antworten sie auf
# das MCP-Protokoll, kommt LibreChat aus SEINEM Container dort an, und stimmt
# der Schlüssel? Jeder Schritt sagt, was zu tun ist, wenn er fehlschlägt.
#
# Aufruf: ./scripts/diagnose-mcp.sh
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.rocm.yml}"

c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'
step() { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_reset"; }
ok()   { printf '  %s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yellow" "$c_reset" "$1"; PROBLEMS=$((PROBLEMS+1)); }
fail() { printf '  %s✗%s %s\n' "$c_red" "$c_reset" "$1"; PROBLEMS=$((PROBLEMS+1)); }
hint() { printf '    %s%s%s\n' "$c_dim" "$1" "$c_reset"; }

PROBLEMS=0
cd "$ROOT_DIR" || exit 1
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

printf '%s' "$c_bold"
cat <<'BANNER'
╔══════════════════════════════════════════════════════╗
║   MCP-Werkzeuge · Fehlersuche                        ║
╚══════════════════════════════════════════════════════╝
BANNER
printf '%s' "$c_reset"

# ── 1) Laufen die Dienste? ──────────────────────────────────────────────────
step "1/6 · Laufen die MCP-Dienste?"
RUNNING=" $(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
for c in mcp sandbox-mcp android-mcp excalidraw-mcp librechat; do
  case "$RUNNING" in
    *" $c "*) ok "$c läuft" ;;
    *) case "$c" in
         android-mcp) warn "$c läuft nicht (nur nötig, wenn du Android-Werkzeuge nutzt)" ;;
         excalidraw-mcp) warn "$c läuft nicht (nur nötig, wenn du Excalidraw-Werkzeuge nutzt)" ;;
         *)
           fail "$c läuft nicht"
           hint "Starten: docker compose -f $COMPOSE_FILE up -d $c"
           ;;
       esac ;;
  esac
done

# Läuft LibreChat? Davon hängen alle Prüfungen ab, die im Container
# stattfinden. Ohne diese Unterscheidung meldet die Fehlersuche lauter
# Folgefehler ("Schlüssel leer", "Konfiguration fehlt") und verdeckt damit
# die eine echte Ursache.
case "$RUNNING" in *" librechat "*) LC_UP=1 ;; *) LC_UP=0 ;; esac
if [ "$LC_UP" -eq 0 ]; then
  printf '\n  %sLibreChat läuft nicht — die Prüfungen 2, 3 und 5/6 finden IM\n' "$c_yellow"
  printf '  Container statt und werden deshalb übersprungen. Erst starten:%s\n' "$c_reset"
  printf '    docker compose -f %s up -d librechat\n' "$COMPOSE_FILE"
fi

# ── 2) Schlüssel vorhanden? ─────────────────────────────────────────────────
step "2/6 · MCP-Schlüssel"
if [ -z "${MCP_API_KEY:-}" ]; then
  fail "MCP_API_KEY fehlt in der .env"
  hint "Das MCP Gateway lehnt Anfragen ohne gültigen Schlüssel ab —"
  hint "LibreChat meldet dann 'MCP tools unavailable'."
  hint "Erzeugen und eintragen: ./scripts/wire-mcp.sh"
else
  ok "MCP_API_KEY steht in der .env"
  if [ "$LC_UP" -eq 0 ]; then
    printf '    %s(ob er im Container ankommt, ist erst nach dem Start prüfbar)%s\n' "$c_dim" "$c_reset"
  else
  # Entscheidend ist nicht die .env, sondern was IM Container ankommt:
  # Compose reicht Variablen nur beim (Neu-)Erzeugen des Containers durch.
  IN_LC="$(docker exec librechat printenv MCP_API_KEY 2>/dev/null)"
  if [ -z "$IN_LC" ]; then
    fail "Im librechat-Container ist MCP_API_KEY LEER"
    hint "Der Container wurde vor dem Eintragen des Schlüssels erzeugt."
    hint "Beheben: docker compose -f $COMPOSE_FILE up -d --force-recreate librechat"
  elif [ "$IN_LC" != "$MCP_API_KEY" ]; then
    fail "Im Container steht ein ANDERER Schlüssel als in der .env"
    hint "Beheben: docker compose -f $COMPOSE_FILE up -d --force-recreate librechat"
  else
    ok "Derselbe Schlüssel ist im librechat-Container angekommen"
  fi
  fi
fi

# ── 3) Antworten die Dienste auf MCP? ───────────────────────────────────────
# Eine echte initialize-Anfrage — nur so zeigt sich, ob dort wirklich ein
# MCP-Server sitzt und den Schlüssel akzeptiert. Ein offener Port sagt nichts.
step "3/6 · Sprechen die Dienste MCP?"
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"diagnose","version":"1.0"}}}'

# Im LibreChat-Image gibt es kein curl — wohl aber node, denn LibreChat IST
# eine Node-Anwendung. Die Anfrage geht deshalb über node; so bleibt die
# Prüfung an genau der Stelle, auf die es ankommt: aus dem Container heraus,
# über dasselbe Docker-Netz, das LibreChat auch selbst benutzt.
HTTP_JS='
const [url, auth, body] = [process.argv[1], process.argv[2], process.argv[3]];
const lib = url.startsWith("https") ? require("https") : require("http");
const headers = {
  "Content-Type": "application/json",
  "Accept": "application/json, text/event-stream",
  "Content-Length": Buffer.byteLength(body),
};
if (auth) headers["Authorization"] = "Bearer " + auth;
const req = lib.request(url, { method: "POST", headers, timeout: 12000 }, (res) => {
  let data = "";
  res.on("data", (c) => (data += c));
  res.on("end", () => {
    console.log(res.statusCode);
    console.log(data.slice(0, 300));
  });
});
req.on("timeout", () => { console.log("000"); console.log("Zeitüberschreitung"); req.destroy(); });
req.on("error", (e) => { console.log("000"); console.log(e.message); });
req.end(body);
'

probe() {
  local name="$1" url="$2" auth="$3" out code rest
  out="$(docker exec librechat node -e "$HTTP_JS" "$url" "$auth" "$INIT" 2>&1)"
  code="$(printf '%s' "$out" | head -1)"
  rest="$(printf '%s' "$out" | tail -n +2)"
  case "$code" in
    200)
      if printf '%s' "$rest" | grep -q 'serverInfo\|protocolVersion'; then
        ok "$name antwortet als MCP-Server"
      else
        warn "$name antwortet mit 200, aber ohne MCP-Inhalt"
        printf '%s\n' "$rest" | head -3 | sed 's/^/      /'
      fi ;;
    401|403)
      fail "$name lehnt den Schlüssel ab (HTTP $code)"
      hint "Schlüssel neu verdrahten: ./scripts/wire-mcp.sh"
      hint "danach: docker compose -f $COMPOSE_FILE up -d --force-recreate librechat" ;;
    404)
      fail "$name: Pfad nicht gefunden (HTTP 404) — falsche URL in librechat.yaml?" ;;
    000)
      fail "$name ist aus dem librechat-Container nicht erreichbar"
      printf '%s\n' "$rest" | head -2 | sed 's/^/      /'
      hint "Läuft der Dienst, und hängen beide im selben Docker-Netz?" ;;
    *)
      fail "$name antwortet unerwartet"
      printf '%s\n' "$out" | head -3 | sed 's/^/      /' ;;
  esac
}

case "$RUNNING" in
  *" librechat "*)
    probe "mcp_gateway"  "http://mcp:3000/mcp"          "${MCP_API_KEY:-}"
    probe "code_sandbox" "http://sandbox-mcp:8000/mcp"  ""
    case "$RUNNING" in *" android-mcp "*) probe "android_build" "http://android-mcp:8000/mcp" "" ;; esac
    case "$RUNNING" in *" excalidraw-mcp "*) probe "excalidraw" "http://excalidraw-mcp:8000/mcp" "" ;; esac ;;
  *) printf '  %s—%s übersprungen: LibreChat läuft nicht\n' "$c_dim" "$c_reset" ;;
esac

# ── 3b) SSRF-Ausnahme deckt ALLE konfigurierten Server ab? ─────────────────
# Ohne mcpSettings.allowedAddresses blockiert LibreChat jedes Ziel mit privater
# IP — und Docker-interne Namen zeigen genau dorthin. Der Fehler im Log lautet
# dann: Domain "http://mcp:3000" is not allowed
#
# Nur zu prüfen, OB der Schlüssel allowedAddresses existiert, reicht nicht -
# live beobachtet: die Liste war da, aber ein neu hinzugekommener Server
# (excalidraw-mcp:8000) fehlte darin. Der alte Check hätte das als "in
# Ordnung" gemeldet. Deshalb hier stattdessen JEDEN in mcpServers
# konfigurierten host:port gegen die tatsächliche allowedAddresses-Liste
# abgleichen und fehlende einzeln benennen.
if [ "$LC_UP" -eq 1 ]; then
  MISSING_ADDR="$(docker exec librechat sh -c 'cat /app/librechat.yaml' 2>/dev/null | python3 -c '
import re, sys
text = sys.stdin.read()
hostports = sorted(set(re.findall(r"url:\s*\"http://([^/\"]+)", text)))
m = re.search(r"allowedAddresses:\s*\n((?:\s*-\s*\"[^\"]+\"\s*\n?)*)", text)
allowed = set(re.findall(r"\"([^\"]+)\"", m.group(1))) if m else set()
print("\n".join(hp for hp in hostports if hp not in allowed))
' 2>/dev/null)"
  if [ -z "$MISSING_ADDR" ]; then
    ok "mcpSettings.allowedAddresses deckt alle konfigurierten Server ab"
  else
    fail "mcpSettings.allowedAddresses deckt nicht alle konfigurierten Server ab"
    printf '%s\n' "$MISSING_ADDR" | while IFS= read -r addr; do
      hint "Fehlt: \"$addr\"  ->  Domain \"http://$addr\" is not allowed"
    done
    hint "Beheben: fehlende(n) Eintrag/Einträge in librechat.yaml unter"
    hint "mcpSettings.allowedAddresses ergänzen, dann:"
    hint "  docker compose -f $COMPOSE_FILE restart librechat"
  fi
fi

# ── 4) Was sagt LibreChat beim Start? ───────────────────────────────────────
step "4/6 · Meldungen von LibreChat"
LOG="$(docker logs librechat 2>&1 | grep -iE 'mcp' | tail -15)"
if [ -z "$LOG" ] && [ "$LC_UP" -eq 0 ]; then
  printf '  %s—%s kein Log: LibreChat läuft nicht\n' "$c_dim" "$c_reset"
elif [ -z "$LOG" ]; then
  warn "Keine MCP-Meldungen im Log — wird die librechat.yaml überhaupt gelesen?"
  hint "Prüfen: docker exec librechat sh -c 'head -5 /app/librechat.yaml'"
  hint "CONFIG_PATH muss auf /app/librechat.yaml zeigen."
else
  printf '%s\n' "$LOG" | sed 's/^/    /'
  if printf '%s' "$LOG" | grep -q 'is not allowed'; then
    fail "LibreChat blockiert die Adressen (SSRF-Schutz)"
    hint "mcpSettings.allowedAddresses fehlt oder deckt nicht alle Dienste ab."
    hint "Beheben: git pull, dann docker compose -f $COMPOSE_FILE restart librechat"
  elif printf '%s' "$LOG" | grep -q 'Requested tool not found\|Tool definition not found'; then
    # Kein Verbindungsproblem: das Modell hat den Werkzeugnamen selbst falsch
    # geschrieben (z.B. "fetch_fetch" statt "fetch-fetch" mit Bindestrich).
    # LibreChat erkennt das korrekt, verbindet zur Sicherheit einmal neu -
    # findet den falschen Namen aber weiterhin nicht und meldet das sauber,
    # statt abzustuerzen. Ein Neustart von librechat aendert daran nichts.
    warn "Modell hat einen falschen/vertippten Werkzeugnamen aufgerufen"
    hint "Kein Fehler in der Verdrahtung - der echte Name steht in Schritt 5"
    hint "unten (meist mit Bindestrich, z.B. 'fetch-fetch'). Sag dem Modell"
    hint "im Chat den korrekten Namen, oder beschreib die Aufgabe statt das"
    hint "Werkzeug beim Namen zu nennen - dann waehlt es selbst richtig."
  elif printf '%s' "$LOG" | grep -qiE 'error|failed|unavailable|refused'; then
    fail "Das Log meldet Fehler (siehe oben)"
  else
    ok "Keine Fehler in den MCP-Meldungen"
  fi
fi

# ── 4b) Wie viele Werkzeuge liefert JEDER Server? ───────────────────────────
# "Initialized with 3 configured servers and 8 tools" klingt gut, kann aber
# bedeuten, dass ein Server gar nichts beigesteuert hat. LibreChat protokolliert
# die Werkzeuge pro Server — das ist die verlaessliche Quelle, nicht die Summe.
step "5/6 · Werkzeuge je Server"
if [ "$LC_UP" -eq 0 ]; then
  printf '  %s—%s übersprungen: LibreChat läuft nicht\n' "$c_dim" "$c_reset"
fi
ALL_LOG="$(docker logs librechat 2>&1)"
# ANSI-Farbcodes raus, BEVOR "Tools: ..." ausgewertet wird: manche Logger
# faerben Werte wie "undefined" ein, und "undefined\x1b[39m" ist streng
# genommen nicht mehr das Wort "undefined" - der Vergleich weiter unten
# wuerde daran vorbeirutschen, ohne dass im Terminal etwas Auffaelliges zu
# sehen waere (die Codes setzen nur die Farbe zurueck, ohne sichtbaren Rest).
ALL_LOG="$(printf '%s' "$ALL_LOG" | sed -E $'s/\x1b\\[[0-9;]*[a-zA-Z]//g')"
GATEWAY_EMPTY=0
for srv in mcp_gateway code_sandbox android_build excalidraw; do
  [ "$LC_UP" -eq 1 ] || break
  # Ist der Server ueberhaupt konfiguriert?
  docker exec librechat sh -c "grep -q '^  ${srv}:' /app/librechat.yaml" 2>/dev/null || continue
  line="$(printf '%s' "$ALL_LOG" | grep -F "[MCP][$srv] Tools:" | tail -1)"
  # "Tools: undefined" heisst: verbunden, aber der Server bietet nichts an.
  # Das als ein Werkzeug zu zaehlen waere schlimmer als gar keine Zahl.
  tools="${line#*Tools: }"
  # \r entfernen und Rand-Leerraum abschneiden: docker logs liefert Zeilen
  # nicht immer sauber getrimmt, und schon ein einziges Leerzeichen vor
  # "undefined" liesse den folgenden Vergleich ins Leere laufen — "undefined"
  # zaehlte dann als ein echtes Werkzeug statt gar keins.
  tools="${tools//$'\r'/}"
  tools="${tools#"${tools%%[![:space:]]*}"}"
  tools="${tools%"${tools##*[![:space:]]}"}"
  case "${tools:-}" in undefined|null|none|"") tools="" ;; esac
  if [ -n "$line" ] && [ -n "$tools" ]; then
    count="$(printf '%s' "$tools" | tr ',' '\n' | grep -c '[a-zA-Z]')"
    ok "$srv: $count Werkzeuge"
    printf '      %s%s%s\n' "$c_dim" "$tools" "$c_reset"
  elif [ -n "$line" ]; then
    fail "$srv ist verbunden, bietet aber KEINE Werkzeuge an (Tools: undefined)"
    [ "$srv" = "mcp_gateway" ] && GATEWAY_EMPTY=1
  else
    fail "$srv liefert KEINE Werkzeuge"
    if [ "$srv" = "mcp_gateway" ]; then
      hint "Das Gateway ist verbunden, meldet aber keine Werkzeuge. Meist sind"
      hint "in MCPHub keine Server aktiv. Nachsehen und nachtragen:"
      hint "  ./scripts/wire-mcp.sh"
      hint "  docker exec mcp cat /var/lib/mcp/mcp_settings.json"
      hint "Danach: docker compose -f $COMPOSE_FILE restart librechat"
    else
      hint "Log ansehen: docker logs librechat 2>&1 | grep '\[MCP\]\[$srv\]'"
    fi
  fi
done

# ── 5) Konfiguration im Container ───────────────────────────────────────────
# Das Gateway direkt fragen, wenn es LibreChat gegenüber nichts anbietet:
# so unterscheidet sich "MCPHub hat keine Server aktiv" von "LibreChat holt
# die Liste nicht ab". Dafür der vollständige MCP-Ablauf — initialize, dann
# notifications/initialized mit der Sitzungskennung, dann tools/list.
if [ "${GATEWAY_EMPTY:-0}" -eq 1 ]; then
  step "5b/6 · Was bietet das Gateway selbst an?"
  LIST_JS='
const [url, auth] = [process.argv[1], process.argv[2]];
const http = require("http");
const base = { "Content-Type": "application/json", "Accept": "application/json, text/event-stream" };
if (auth) base["Authorization"] = "Bearer " + auth;
const post = (payload, sid) => new Promise((res) => {
  const body = JSON.stringify(payload);
  const headers = { ...base, "Content-Length": Buffer.byteLength(body) };
  if (sid) headers["mcp-session-id"] = sid;
  const req = http.request(url, { method: "POST", headers, timeout: 15000 }, (r) => {
    let d = ""; r.on("data", (c) => (d += c));
    r.on("end", () => res({ status: r.statusCode, sid: r.headers["mcp-session-id"], body: d }));
  });
  req.on("error", (e) => res({ status: 0, body: e.message }));
  req.on("timeout", () => { req.destroy(); res({ status: 0, body: "Zeitüberschreitung" }); });
  req.end(body);
});
// SSE-Antworten ("data: {...}") wie einfaches JSON behandeln
const parse = (t) => { for (const l of t.split("\n")) { const s = l.startsWith("data:") ? l.slice(5).trim() : l.trim();
  if (s.startsWith("{")) { try { return JSON.parse(s); } catch (e) {} } } return null; };
(async () => {
  const init = await post({ jsonrpc: "2.0", id: 1, method: "initialize",
    params: { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "diagnose", version: "1" } } });
  if (init.status !== 200) return console.log("FEHLER initialize: " + init.status + " " + init.body.slice(0, 120));
  const sid = init.sid;
  await post({ jsonrpc: "2.0", method: "notifications/initialized" }, sid);
  const list = await post({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }, sid);
  const j = parse(list.body);
  const tools = j && j.result && j.result.tools;
  if (!tools) return console.log("KEINE_LISTE " + list.status + " " + list.body.slice(0, 160));
  console.log("ANZAHL " + tools.length);
  console.log(tools.map((t) => t.name).join(", "));
})();
'
  out="$(docker exec librechat node -e "$LIST_JS" "http://mcp:3000/mcp" "${MCP_API_KEY:-}" 2>&1)"
  # War in LibreChats eigenem Log "OAuth Required: true" fuer den Gateway
  # vermerkt? Dann ist NICHT ein einfacher Neustart die Loesung, sondern
  # MCPHubs eingebauter OAuth-Server muss aus - siehe wire-mcp.sh.
  GATEWAY_OAUTH="$(printf '%s' "$ALL_LOG" | grep -F "[MCP][mcp_gateway] OAuth Required:" | tail -1)"
  case "$out" in
    ANZAHL\ 0*)
      fail "Das Gateway selbst meldet 0 Werkzeuge"
      hint "In MCPHub ist kein Server aktiv. Nachtragen und ansehen:"
      hint "  ./scripts/wire-mcp.sh"
      hint "  docker exec mcp cat /var/lib/mcp/mcp_settings.json"
      hint "Danach: docker compose -f $COMPOSE_FILE restart librechat" ;;
    ANZAHL\ *)
      warn "Das Gateway bietet Werkzeuge an, LibreChat sieht sie aber nicht:"
      printf '%s\n' "$out" | tail -n +2 | sed 's/^/      /'
      case "$GATEWAY_OAUTH" in
        *"OAuth Required: true"*)
          hint "Ursache: LibreChat prueft OAuth-Bedarf beim Start OHNE den"
          hint "konfigurierten Header. Caddy vor MCPHub sichert dabei auch die"
          hint "OAuth-Erkennungspfade mit dem Bearer-Key ab, die Pruefung"
          hint "bekommt darum 401 statt 404 und haelt den Server faelschlich"
          hint "fuer OAuth-pflichtig - der Bearer-Key selbst funktioniert"
          hint "einwandfrei (wie eben, direkt getestet)."
          hint "Behebung: requiresOAuth: false steht seit git pull bei"
          hint "mcp_gateway in librechat.yaml. Falls noch nicht aktuell:"
          hint "  git pull"
          hint "  docker compose -f $COMPOSE_FILE restart librechat" ;;
        *)
          hint "Meist hilft: docker compose -f $COMPOSE_FILE restart librechat" ;;
      esac ;;
    *)
      fail "Werkzeugliste nicht abrufbar"
      printf '%s\n' "$out" | head -3 | sed 's/^/      /' ;;
  esac
fi

step "6/6 · Konfiguration im Container"
if [ "$LC_UP" -eq 0 ]; then
  printf '  %s—%s übersprungen: LibreChat läuft nicht\n' "$c_dim" "$c_reset"
elif docker exec librechat sh -c 'grep -q "^mcpServers:" /app/librechat.yaml' 2>/dev/null; then
  ok "mcpServers steht in der Konfiguration"
  docker exec librechat sh -c "sed -n '/^mcpServers:/,\$p' /app/librechat.yaml | grep -E '^  [a-z_]+:|url:'" 2>/dev/null | sed 's/^/    /'
else
  fail "In /app/librechat.yaml steht kein mcpServers-Block"
  hint "Ist librechat/librechat.yaml eingehängt? docker compose -f $COMPOSE_FILE up -d --force-recreate librechat"
fi

# ── Fazit ───────────────────────────────────────────────────────────────────
step "Fazit"
if [ "$PROBLEMS" -eq 0 ]; then
  ok "Technisch ist alles in Ordnung."
  printf '\n  %sBleibt die Meldung "AGENT_EXPECTED_MCP_TOOLS_UNAVAILABLE", liegt es am\n' "$c_dim"
  printf '  Agenten selbst: In LibreChat unter Agenten -> Bearbeiten -> Werkzeuge\n'
  printf '  müssen die MCP-Werkzeuge ausgewählt sein. Ein Agent mit abgewählten\n'
  printf '  oder umbenannten Werkzeugen meldet genau diesen Fehler.%s\n' "$c_reset"
elif [ "$LC_UP" -eq 0 ]; then
  printf '  %sLibreChat läuft nicht — das ist die Ursache. Starten und erneut prüfen:%s\n' "$c_yellow" "$c_reset"
  printf '    docker compose -f %s up -d librechat && ./scripts/diagnose-mcp.sh\n' "$COMPOSE_FILE"
else
  printf '  %s%d Punkt(e) zu klären — siehe oben.%s\n' "$c_yellow" "$PROBLEMS" "$c_reset"
fi
printf '\n  %sHäufigste Ursache:%s LibreChat verbindet die MCP-Server beim START.\n' "$c_bold" "$c_reset"
printf '  Lief ein Dienst damals noch nicht (oder wurde er seither neu erzeugt),\n'
printf '  bleibt er für LibreChat verschwunden, bis LibreChat selbst neu startet:\n\n'
printf '    docker compose -f %s restart librechat\n' "$COMPOSE_FILE"
printf '\n  %sDasselbe gilt nach jeder Änderung an librechat.yaml.%s\n' "$c_dim" "$c_reset"
