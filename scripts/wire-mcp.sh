#!/usr/bin/env bash
#
# Verdrahtet MCP Gateway mit LiteLLM UND mit Open WebUI.
#
# Das vanilla-LiteLLM-Image (im Gegensatz zu hwdsl2/litellm-server) teilt
# API-Keys nicht automatisch über Volumes. Dieses Skript holt den vom
# mcp-Container erzeugten API-Key, schreibt ihn als MCP_API_KEY in die .env
# und startet LiteLLM neu, damit litellm/config.yaml (mcp_servers.*.auth_value
# = os.environ/MCP_API_KEY) ihn übernimmt.
#
# Open WebUI spricht kein rohes MCP, sondern nur OpenAPI — deshalb rendert
# dieses Skript zusätzlich mcpo/config.json (mit dem echten Key statt des
# Platzhalters __MCP_API_KEY__) und startet den mcpo-Dienst (MCP→OpenAPI-
# Proxy), den Open WebUI unter Admin-Einstellungen → Werkzeuge einbinden kann.
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

# ── Austausch-Ordner in der .env nachtragen ─────────────────────────────────
#
# MCP_FILESYSTEM_DIRS steht als konkreter Wert in der .env (install.sh
# schreibt ihn dort hinein) - der Vorgabewert im Compose-File
# (MCP_FILESYSTEM_DIRS:-...) greift also nur bei einer .env, die den
# Schlüssel noch gar nicht kennt. Bei einer bestehenden Installation muss
# "/exchange" hier von Hand nachgetragen werden, sonst sieht der
# mcp-Container ihn nie - und der Patch weiter unten (der genau diese
# Variable ausliest) würde ihn ebenfalls nicht eintragen.
# shellcheck source=scripts/env-lib.sh
. "$SCRIPT_DIR/env-lib.sh"
ENV_DIRS_CHANGED=0
if [ -f "$ENV_FILE" ]; then
  CUR_DIRS="$(env_get MCP_FILESYSTEM_DIRS)"
  case ",${CUR_DIRS}," in
    *,/exchange,*) ;;  # schon drin
    *)
      NEW_DIRS="${CUR_DIRS:-/vault,/workspace},/exchange"
      env_set MCP_FILESYSTEM_DIRS "$NEW_DIRS"
      ENV_DIRS_CHANGED=1
      ok "MCP_FILESYSTEM_DIRS in der .env um /exchange ergänzt."
      ;;
  esac
fi

if [ "$ENV_DIRS_CHANGED" -eq 1 ]; then
  # Eine neue Umgebungsvariable erreicht einen LAUFENDEN Container nicht -
  # "restart" allein wuerde die alte, alte env(!) nur erneut starten. Es
  # muss neu ERZEUGT werden, damit mcp den aktualisierten Wert bekommt.
  info "mcp neu erzeugen, damit es den neuen Ordner sieht…"
  $DC -f "$COMPOSE_FILE" up -d --force-recreate mcp >/dev/null
  for i in $(seq 1 40); do
    docker exec mcp mcp_manage --getkey >/dev/null 2>&1 && break
    sleep 3
    [ "$i" -eq 40 ] && die "mcp wurde nach dem Neuerzeugen nicht rechtzeitig bereit. Prüfe: docker logs mcp"
  done
fi

# ── Eigene/nicht automatisch registrierte MCP-Server nachtragen ────────────
#
# Bei manchen Installationen registriert hwdsl2/mcp-gateway "filesystem"
# beim allerersten Start nicht automatisch, obwohl MCP_SERVERS es enthält
# (siehe README, Abschnitt "Zwei-Wege-Sync" für Details/Reproduktion). Und
# unser eigenes "time"-Werkzeug (mcp-tools/get_time.py) ist dem Image von
# Haus aus gar nicht bekannt. Beides wird hier idempotent nachgetragen -
# ändert nichts, falls schon vorhanden.
info "Prüfe, ob 'filesystem' und 'time' bei mcp registriert sind…"
PATCH_RESULT="$(docker exec mcp node -e '
const fs = require("fs");
const path = "/var/lib/mcp/mcp_settings.json";
const data = JSON.parse(fs.readFileSync(path, "utf8"));
data.mcpServers = data.mcpServers || {};
let changed = false;
const dirs = (process.env.MCP_FILESYSTEM_DIRS || "/vault,/workspace")
  .split(",").map(d => d.trim()).filter(Boolean);
if (!data.mcpServers.filesystem) {
  data.mcpServers.filesystem = {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", ...dirs],
  };
  changed = true;
} else {
  // Schon vorhanden: fehlende Verzeichnisse ergänzen, statt den Eintrag in
  // Ruhe zu lassen. Sonst bekäme eine bestehende Installation, die nur
  // /vault kennt, ein später hinzugekommenes Verzeichnis (z. B. den
  // Android-Arbeitsbereich) nie zu sehen.
  const args = data.mcpServers.filesystem.args || [];
  for (const dir of dirs) {
    if (!args.includes(dir)) {
      args.push(dir);
      changed = true;
    }
  }
  data.mcpServers.filesystem.args = args;
}
if (!data.mcpServers.time) {
  data.mcpServers.time = {
    command: "python3",
    args: ["/opt/mcp-tools/get_time.py"],
  };
  changed = true;
}
// Den eingebauten OAuth-Server von MCPHub abschalten: dieser Stack nutzt
// den statischen Bearer-Key (MCP_API_KEY), keine dynamische Client-
// Registrierung. Bleibt er an, meldet MCPHub den /mcp-Endpunkt als
// "OAuth erforderlich" - LibreChats MCP-Client bricht die Aushandlung dann
// vorzeitig ab (Capabilities/Tools bleiben "undefined"), obwohl der
// Bearer-Key fuer echte Werkzeugaufrufe einwandfrei funktioniert. Ein
// direkter Aufruf ohne OAuth-Handshake bekommt die Werkzeuge normal.
data.systemConfig = data.systemConfig || {};
data.systemConfig.oauthServer = data.systemConfig.oauthServer || {};
if (data.systemConfig.oauthServer.enabled !== false) {
  data.systemConfig.oauthServer.enabled = false;
  changed = true;
}
if (changed) {
  fs.writeFileSync(path, JSON.stringify(data, null, 2));
  console.log("CHANGED");
} else {
  console.log("UNCHANGED");
}
')"

if [ "$PATCH_RESULT" = "CHANGED" ]; then
  ok "Konfiguration angepasst, starte mcp neu…"
  $DC -f "$COMPOSE_FILE" restart mcp >/dev/null
  for i in $(seq 1 40); do
    docker exec mcp mcp_manage --getkey >/dev/null 2>&1 && break
    sleep 3
    [ "$i" -eq 40 ] && die "mcp wurde nach dem Neustart nicht rechtzeitig bereit. Prüfe: docker logs mcp"
  done

  # LibreChat verbindet seine MCP-Server nur beim eigenen Start und fragt
  # danach nie wieder nach (siehe documentation/de/librechat.md). Ein
  # mcp-Neustart eben - egal aus welchem der obigen Gruende - macht seinen
  # zwischengespeicherten Stand (moeglicherweise "OAuth erforderlich" oder
  # eine alte, unvollstaendige Werkzeugliste) ungueltig. Ohne diesen
  # Neustart hier bliebe LibreChat auf dem alten Stand haengen, bis jemand
  # von Hand draufkommt - genau das hat zuvor zu langer Fehlersuche gefuehrt.
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx librechat; then
    info "LibreChat neu starten, damit es die aktualisierten MCP-Werkzeuge sieht…"
    $DC -f "$COMPOSE_FILE" restart librechat >/dev/null
    ok "LibreChat neu gestartet."
  fi
else
  ok "'filesystem', 'time' und die OAuth-Einstellung waren schon korrekt, kein Neustart nötig."
fi

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

# ── mcpo (MCP → OpenAPI, für Open WebUI) ────────────────────────────────────
TEMPLATE="$ROOT_DIR/mcpo/config.template.json"
RENDERED="$ROOT_DIR/mcpo/config.json"
if [ -f "$TEMPLATE" ]; then
  # Falls config.json noch nie eine echte Datei war, hat Docker beim allerersten
  # Start (ohne vorheriges install.sh) ein leeres VERZEICHNIS an dieser Stelle
  # angelegt (Bind-Mount einer fehlenden Datei). Das muss weg, sonst schlägt
  # sowohl das Schreiben hier als auch mcpo selbst mit "Is a directory" fehl.
  if [ -d "$RENDERED" ]; then
    warn "mcpo/config.json ist ein Verzeichnis (Docker-Artefakt vom allerersten Start) — räume das auf…"
    $DC -f "$COMPOSE_FILE" rm -sf mcpo >/dev/null 2>&1 || true
    rmdir "$RENDERED" 2>/dev/null \
      || die "Konnte mcpo/config.json (Verzeichnis) nicht entfernen — manuell prüfen: ls -la '$RENDERED'"
  fi

  info "Rendere mcpo/config.json (mit echtem Key statt Platzhalter)…"
  sed "s#__MCP_API_KEY__#${MCP_KEY}#" "$TEMPLATE" > "$RENDERED"
  chmod 600 "$RENDERED"
  ok "mcpo/config.json geschrieben (enthält den Key im Klartext, nicht committen — .gitignore deckt das ab)."

  info "Erzeuge mcpo neu, damit die Konfiguration sicher übernommen wird…"
  $DC -f "$COMPOSE_FILE" up -d --force-recreate mcpo >/dev/null

  info "Warte, bis mcpo bereit ist…"
  for i in $(seq 1 30); do
    if docker exec mcpo python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/docs')" >/dev/null 2>&1; then
      ok "mcpo ist bereit."
      break
    fi
    sleep 2
  done
else
  warn "mcpo/config.template.json nicht gefunden — mcpo-Schritt übersprungen."
fi

echo
echo "Prüfen (LiteLLM):        docker logs litellm | grep -i mcp"
echo "Prüfen (mcpo/Open WebUI): docker logs mcpo"
echo "Direkter Test:            docker exec mcp mcp_manage --getkey  (gleicher Key wie in .env)"
echo
echo "In Open WebUI einbinden: Admin-Einstellungen → Werkzeuge → Werkzeug-Server verwalten,"
echo "  URL: http://mcpo:8000/mcp_gateway   (Dateisystem, Web, GitHub, ...)"
echo "  URL: http://mcpo:8000/code_sandbox  (run_python, run_shell)"
