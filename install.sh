#!/usr/bin/env bash
#
# Self-Hosted AI Stack — Installer für AMD ROCm (Ryzen AI Max+ 395 / Strix Halo)
#
# Prüft die Voraussetzungen, richtet die Firewall (LAN-only) ein, erzeugt die
# .env, startet den kompletten Stack (docker-compose.rocm.yml), lädt das
# Standardmodell und trägt alle Ollama-Modelle bei LiteLLM ein.
#
# Aufruf:   sudo ./install.sh
#           ./install.sh --check-only     # nur prüfen, nichts ändern
#           DEFAULT_MODEL=qwen2.5:14b ./install.sh
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

# ── Konfiguration (per Env oder .env überschreibbar) ────────────────────────
COMPOSE_FILE="docker-compose.rocm.yml"
DEFAULT_MODEL="${DEFAULT_MODEL:-gemma3:12b}"   # gemma4 gibt's noch nicht -> gemma3:12b
HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.5.1}"  # gfx1151 (Strix Halo)
FIREWALL_MODE="${FIREWALL_MODE:-lan}"          # lan | open | none
MIN_RAM_GB="${MIN_RAM_GB:-16}"

PORT_WEBUI="${PORT_WEBUI:-3001}"
PORT_LITELLM="${PORT_LITELLM:-4000}"
PORT_DASHBOARD="${PORT_DASHBOARD:-8600}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && CHECK_ONLY=1

# ── Ausgabe-Helfer ──────────────────────────────────────────────────────────
c_reset=$'\033[0m'; c_blue=$'\033[0;34m'; c_green=$'\033[0;32m'
c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'; c_bold=$'\033[1m'
step()  { printf '\n%s▸ %s%s\n' "$c_bold" "$1" "$c_reset"; }
info()  { printf '%s•%s %s\n' "$c_blue" "$c_reset" "$1"; }
ok()    { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
warn()  { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$1"; }
err()   { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$1"; }
die()   { err "$1"; exit 1; }

WARNINGS=0
note_warn() { warn "$1"; WARNINGS=$((WARNINGS+1)); }

# ── Root/sudo ───────────────────────────────────────────────────────────────
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    note_warn "Kein root und kein sudo — Firewall/Gruppen-Schritte werden ggf. übersprungen."
  fi
fi

# Realer Benutzer (auch unter sudo), für Gruppenzuordnung
TARGET_USER="${SUDO_USER:-$(id -un)}"

printf '%s' "$c_bold"
cat <<'BANNER'
╔══════════════════════════════════════════════════════╗
║   Self-Hosted AI Stack · AMD ROCm Installer          ║
║   Ollama · Open WebUI · LiteLLM · Dashboard          ║
╚══════════════════════════════════════════════════════╝
BANNER
printf '%s' "$c_reset"

# ════════════════════════════════════════════════════════════════════════════
step "1/7 · System prüfen"

[ "$(uname -s)" = "Linux" ] || die "Dieser Stack braucht Linux."
ok "Betriebssystem: Linux ($(uname -m))"

# Distro / Paketmanager erkennen
PKG=""
if command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"; fi
[ -n "$PKG" ] && ok "Paketmanager: $PKG" || note_warn "Kein bekannter Paketmanager (apt/dnf/pacman)."

# RAM
if [ -r /proc/meminfo ]; then
  RAM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  RAM_GB=$(( RAM_KB / 1024 / 1024 ))
  if [ "$RAM_GB" -ge "$MIN_RAM_GB" ]; then ok "RAM: ${RAM_GB} GB"
  else note_warn "RAM: nur ${RAM_GB} GB (empfohlen ≥ ${MIN_RAM_GB} GB für große Modelle)."; fi
fi

# Freier Speicherplatz
FREE_GB="$(df -BG --output=avail "$ROOT_DIR" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)"
if [ "${FREE_GB:-0}" -ge 30 ]; then ok "Freier Speicher: ${FREE_GB} GB"
else note_warn "Freier Speicher: ${FREE_GB} GB (Modelle brauchen viel Platz)."; fi

# ════════════════════════════════════════════════════════════════════════════
step "2/7 · AMD-GPU / ROCm prüfen"

GPU_OK=1
if lspci 2>/dev/null | grep -iE 'VGA|Display|3D' | grep -iq 'AMD\|ATI'; then
  ok "AMD-GPU erkannt: $(lspci 2>/dev/null | grep -iE 'VGA|Display|3D' | grep -i 'AMD\|ATI' | head -1 | cut -d: -f3- | sed 's/^ *//')"
else
  note_warn "Keine AMD-GPU über lspci erkannt (evtl. lspci fehlt)."; GPU_OK=0
fi

if lsmod 2>/dev/null | grep -q '^amdgpu'; then ok "Kernel-Modul amdgpu geladen."
else note_warn "Kernel-Modul amdgpu nicht geladen — GPU-Beschleunigung geht dann nicht."; GPU_OK=0; fi

if [ -e /dev/kfd ]; then ok "/dev/kfd vorhanden (ROCm-Compute-Interface)."
else note_warn "/dev/kfd fehlt — ROCm-Treiber/kfd nicht aktiv. Ollama läuft dann auf CPU."; GPU_OK=0; fi

if [ -d /dev/dri ] && ls /dev/dri/renderD* >/dev/null 2>&1; then ok "/dev/dri Render-Node vorhanden."
else note_warn "/dev/dri/renderD* fehlt."; GPU_OK=0; fi

# GIDs von video/render ermitteln (für group_add im Compose)
VIDEO_GID="$(getent group video 2>/dev/null | cut -d: -f3 || true)"; VIDEO_GID="${VIDEO_GID:-44}"
RENDER_GID="$(getent group render 2>/dev/null | cut -d: -f3 || true)"; RENDER_GID="${RENDER_GID:-993}"
ok "Gruppen-GIDs: video=${VIDEO_GID}, render=${RENDER_GID}"

# Benutzer den GPU-Gruppen hinzufügen
if [ "$CHECK_ONLY" -eq 0 ] && [ -n "$SUDO$( [ "$(id -u)" -eq 0 ] && echo root )" ]; then
  for grp in video render; do
    if getent group "$grp" >/dev/null 2>&1 && ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
      $SUDO usermod -aG "$grp" "$TARGET_USER" 2>/dev/null \
        && ok "Benutzer '$TARGET_USER' zur Gruppe '$grp' hinzugefügt (Neu-Login nötig)." \
        || note_warn "Konnte '$TARGET_USER' nicht zu '$grp' hinzufügen."
    fi
  done
fi

[ "$GPU_OK" -eq 1 ] && ok "ROCm-Voraussetzungen erfüllt." \
  || note_warn "ROCm nicht vollständig. Installiere die AMD-Treiber (amdgpu-dkms/ROCm) — der Stack startet trotzdem, nutzt dann aber die CPU."

# ════════════════════════════════════════════════════════════════════════════
step "3/7 · Docker prüfen"

if command -v docker >/dev/null 2>&1; then
  ok "Docker: $(docker --version 2>/dev/null | sed 's/,.*//')"
else
  if [ "$CHECK_ONLY" -eq 0 ]; then
    warn "Docker nicht gefunden — installiere es…"
    curl -fsSL https://get.docker.com | $SUDO sh || die "Docker-Installation fehlgeschlagen."
    $SUDO systemctl enable --now docker 2>/dev/null || true
    ok "Docker installiert."
  else
    die "Docker nicht installiert."
  fi
fi

if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose: $(docker compose version --short 2>/dev/null)"
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  ok "Docker Compose (v1): $(docker-compose version --short 2>/dev/null)"
  DC="docker-compose"
else
  die "Docker Compose Plugin fehlt. Installiere 'docker-compose-plugin'."
fi

if ! docker info >/dev/null 2>&1; then
  note_warn "Docker-Daemon nicht erreichbar (läuft er? Bist du in der 'docker'-Gruppe?)."
fi

# ════════════════════════════════════════════════════════════════════════════
step "4/7 · Firewall (Modus: ${FIREWALL_MODE})"

detect_subnet() {
  ip -o -f inet addr show scope global 2>/dev/null \
    | awk '{print $4}' | head -1 \
    | awk -F/ '{split($1,a,"."); print a[1]"."a[2]"."a[3]".0/24"}'
}
LAN_SUBNET="${LAN_SUBNET:-$(detect_subnet)}"
LAN_SUBNET="${LAN_SUBNET:-192.168.0.0/16}"

if [ "$CHECK_ONLY" -eq 1 ] || [ "$FIREWALL_MODE" = "none" ]; then
  info "Firewall wird nicht verändert (Subnetz erkannt: ${LAN_SUBNET})."
else
  if ! command -v ufw >/dev/null 2>&1 && [ "$PKG" = "apt" ]; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq ufw || note_warn "ufw-Installation fehlgeschlagen."
  fi
  if command -v ufw >/dev/null 2>&1; then
    $SUDO ufw allow OpenSSH >/dev/null 2>&1 || $SUDO ufw allow 22/tcp >/dev/null 2>&1 || true
    if [ "$FIREWALL_MODE" = "lan" ]; then
      for p in "$PORT_WEBUI" "$PORT_LITELLM" "$PORT_DASHBOARD"; do
        $SUDO ufw allow from "$LAN_SUBNET" to any port "$p" proto tcp >/dev/null 2>&1 || true
      done
      ok "Firewall: SSH offen; Ports ${PORT_WEBUI}/${PORT_LITELLM}/${PORT_DASHBOARD} nur aus ${LAN_SUBNET}."
    else
      for p in "$PORT_WEBUI" "$PORT_LITELLM" "$PORT_DASHBOARD"; do
        $SUDO ufw allow "$p"/tcp >/dev/null 2>&1 || true
      done
      note_warn "Firewall: Ports ${PORT_WEBUI}/${PORT_LITELLM}/${PORT_DASHBOARD} für ALLE offen (nur mit HTTPS davor empfohlen)."
    fi
    $SUDO ufw --force enable >/dev/null 2>&1 || true
  else
    note_warn "ufw nicht verfügbar — Firewall bitte manuell einrichten."
  fi
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  step "Prüfung abgeschlossen"
  [ "$WARNINGS" -eq 0 ] && ok "Keine Warnungen — bereit für die Installation." \
    || warn "$WARNINGS Warnung(en). Siehe oben. Der Stack startet trotzdem (ggf. ohne GPU)."
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
step "5/7 · Konfiguration schreiben (.env)"

rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; }

if [ -f .env ]; then
  info "Bestehende .env gefunden — behalte vorhandene Secrets."
  # shellcheck disable=SC1091
  set -a; . ./.env; set +a
fi
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(rand 32)}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-$(rand 40)}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(rand 40)}"

cat > .env <<EOF
# Automatisch erzeugt von install.sh — enthält Secrets, nicht committen!
COMPOSE_FILE=${COMPOSE_FILE}

# Standardmodell (mit einer Zeile änderbar; 'gemma4' existiert noch nicht -> gemma3:12b)
DEFAULT_MODEL=${DEFAULT_MODEL}

# AMD-GPU / ROCm (Strix Halo = gfx1151)
HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}
VIDEO_GID=${VIDEO_GID}
RENDER_GID=${RENDER_GID}
OLLAMA_KEEP_ALIVE=30m

# Ports
PORT_WEBUI=${PORT_WEBUI}
PORT_LITELLM=${PORT_LITELLM}
PORT_DASHBOARD=${PORT_DASHBOARD}
PORT_OLLAMA=11434
PORT_WHISPER=9000
PORT_EMBEDDINGS=8000

# Secrets
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}

# Firewall
LAN_SUBNET=${LAN_SUBNET}
EOF
chmod 600 .env
ok ".env geschrieben (Rechte 600)."

# ════════════════════════════════════════════════════════════════════════════
step "6/7 · Stack starten"

info "Ziehe Images und starte Container (kann beim ersten Mal dauern)…"
$DC -f "$COMPOSE_FILE" up -d

info "Warte, bis Ollama bereit ist…"
for i in $(seq 1 60); do
  if docker exec ollama ollama list >/dev/null 2>&1; then ok "Ollama ist bereit."; break; fi
  sleep 3
  [ "$i" -eq 60 ] && note_warn "Ollama wurde nicht rechtzeitig bereit — prüfe 'docker logs ollama'."
done

info "Lade Standardmodell: ${DEFAULT_MODEL} (das dauert je nach Größe)…"
if docker exec ollama ollama pull "$DEFAULT_MODEL"; then
  ok "Modell ${DEFAULT_MODEL} geladen."
else
  note_warn "Konnte ${DEFAULT_MODEL} nicht laden. Prüfe den Modellnamen (z. B. gemma3:12b, llama3.1:8b)."
fi

# GPU-Nutzung kurz prüfen
if docker exec ollama sh -c 'command -v rocminfo >/dev/null 2>&1 && rocminfo' >/dev/null 2>&1; then
  ok "ROCm im Ollama-Container verfügbar (GPU wird genutzt)."
else
  info "Hinweis: Konnte ROCm im Container nicht bestätigen — mit 'docker logs ollama' prüfen, ob die GPU erkannt wurde."
fi

# ════════════════════════════════════════════════════════════════════════════
step "7/7 · Modelle bei LiteLLM eintragen"

info "Warte auf LiteLLM…"
for i in $(seq 1 40); do
  if curl -sf "http://localhost:${PORT_LITELLM}/health/liveliness" >/dev/null 2>&1; then ok "LiteLLM ist bereit."; break; fi
  sleep 3
done
bash "$ROOT_DIR/scripts/sync-ollama-models.sh" || note_warn "Modell-Sync unvollständig — später erneut ausführen: ./scripts/sync-ollama-models.sh"

# ════════════════════════════════════════════════════════════════════════════
IP="$(ip -o -f inet addr show scope global 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1)"
IP="${IP:-<server-ip>}"

step "Fertig! 🎉"
cat <<EOF

  ${c_bold}Zugriff:${c_reset}
    Dashboard    →  http://${IP}:${PORT_DASHBOARD}
    Chat (WebUI) →  http://${IP}:${PORT_WEBUI}
    LiteLLM-UI   →  http://${IP}:${PORT_LITELLM}/ui   (Login: admin / Master-Key aus .env)

  ${c_bold}Nützliche Befehle:${c_reset}
    Status         ${DC} -f ${COMPOSE_FILE} ps
    Logs           ${DC} -f ${COMPOSE_FILE} logs -f <dienst>
    Modell laden   docker exec ollama ollama pull <modell>
    Modelle syncen ./scripts/sync-ollama-models.sh
    Stoppen        ${DC} -f ${COMPOSE_FILE} down

EOF
[ "$WARNINGS" -gt 0 ] && warn "$WARNINGS Warnung(en) während der Installation — bitte oben prüfen."
ok "Viel Spaß mit deinem privaten KI-Stack!"
