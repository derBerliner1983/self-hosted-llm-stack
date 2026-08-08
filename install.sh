#!/usr/bin/env bash
#
# Self-Hosted AI Stack — Installer für AMD ROCm (Ryzen AI Max+ 395 / Strix Halo)
#
# Prüft die Voraussetzungen, richtet die Firewall (LAN-only) ein, erzeugt die
# .env, startet den kompletten Stack (docker-compose.rocm.yml), lädt das
# Standardmodell, verdrahtet MCP Gateway mit LiteLLM und trägt alle
# Ollama-Modelle bei LiteLLM ein.
#
# Aufruf:   sudo ./install.sh
#           ./install.sh --check-only        # nur prüfen, nichts ändern
#           DEFAULT_MODEL=qwen2.5:14b ./install.sh
#           sudo ./install.sh --install-drivers  # AMD-Kernel-Treiber (amdgpu-dkms) installieren
#           sudo ./install.sh --skip-drivers     # Treiber-Installation nie anbieten
#           sudo ./install.sh --uninstall    # Container/Netze entfernen, Daten behalten
#           sudo ./install.sh --purge        # ALLES entfernen (auch Modelle/Chats/DB!)
#           ./install.sh --help
#
# --uninstall/--purge räumen sowohl den neuen ROCm-Stack als auch den alten
# Stack (docker-compose.yml, AnythingLLM/hwdsl2-Images) auf.
#
# This file is part of Self-Hosted AI Stack. MIT License.

set -euo pipefail

# ── Konfiguration (per Env oder .env überschreibbar) ────────────────────────
COMPOSE_FILE="docker-compose.rocm.yml"
DEFAULT_MODEL="${DEFAULT_MODEL:-gemma4:12b}"     # gewünschtes Standardmodell
FALLBACK_MODEL="${FALLBACK_MODEL:-gemma3:12b}"   # falls DEFAULT_MODEL (noch) nicht existiert
HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.5.1}"  # gfx1151 (Strix Halo)
FIREWALL_MODE="${FIREWALL_MODE:-lan}"          # lan | open | none
MIN_RAM_GB="${MIN_RAM_GB:-16}"

PORT_WEBUI="${PORT_WEBUI:-3001}"
PORT_LITELLM="${PORT_LITELLM:-4000}"
PORT_DASHBOARD="${PORT_DASHBOARD:-8600}"
PORT_VAULT_BRIDGE="${PORT_VAULT_BRIDGE:-8700}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

CHECK_ONLY=0
MODE="install"   # install | uninstall | purge
ASSUME_YES=0
INSTALL_AMD_DRIVERS="${INSTALL_AMD_DRIVERS:-auto}"   # auto | yes | no
for arg in "$@"; do
  case "$arg" in
    --check-only)      CHECK_ONLY=1 ;;
    --install-drivers) INSTALL_AMD_DRIVERS="yes" ;;
    --skip-drivers)    INSTALL_AMD_DRIVERS="no" ;;
    --uninstall)       MODE="uninstall" ;;
    --purge)           MODE="purge" ;;
    -y|--yes)          ASSUME_YES=1 ;;
    -h|--help)
      sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'Unbekannte Option: %s (--help für Hilfe)\n' "$arg" >&2; exit 2 ;;
  esac
done

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

# ── Docker-Compose-Befehl ermitteln ─────────────────────────────────────────
resolve_dc() {
  if docker compose version >/dev/null 2>&1; then DC="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
  else DC=""; fi
}

# ── AMD-Kernel-Treiber (amdgpu-dkms) installieren ───────────────────────────
# Es wird bewusst NUR der Kernel-Treiber installiert (liefert /dev/kfd + /dev/dri).
# Die ROCm-Userspace-Bibliotheken bringt das ollama/ollama:rocm-Image selbst mit.
# Rückgabe: 0 = installiert (evtl. Reboot nötig), 1 = nicht möglich/abgebrochen.
install_amd_drivers() {
  local codename amdgpu_deb url rocm_ver amdgpu_pkg_ver

  if [ "$PKG" != "apt" ]; then
    note_warn "Automatische Treiber-Installation ist nur für apt (Ubuntu/Debian) umgesetzt."
    info "Für Fedora/Arch bitte den amdgpu/ROCm-Treiber der Distribution installieren:"
    info "  https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html"
    return 1
  fi
  command -v curl >/dev/null 2>&1 || $SUDO apt-get install -y -qq curl || true

  codename=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  fi
  info "System: ${PRETTY_NAME:-Debian/Ubuntu} (Codename: ${codename:-unbekannt})"
  if [ -z "$codename" ]; then
    note_warn "Konnte den Ubuntu-Codename nicht ermitteln — Treiber bitte manuell installieren."
    return 1
  fi

  # Versionen überschreibbar per Env, falls AMD die Pfade ändert.
  rocm_ver="${ROCM_VERSION:-6.4.1}"
  amdgpu_pkg_ver="${AMDGPU_INSTALL_VERSION:-6.4.60401-1}"

  info "Installiere Kernel-Header (für den DKMS-Build nötig)…"
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y -qq "linux-headers-$(uname -r)" "linux-modules-extra-$(uname -r)" 2>/dev/null \
    || note_warn "Passende Kernel-Header/-Module nicht gefunden — DKMS-Build könnte scheitern."

  amdgpu_deb="amdgpu-install_${amdgpu_pkg_ver}_all.deb"
  url="https://repo.radeon.com/amdgpu-install/${rocm_ver}/ubuntu/${codename}/${amdgpu_deb}"
  info "Lade AMD-Installer: ${url}"
  if ! curl -fsSL -o "/tmp/${amdgpu_deb}" "$url"; then
    note_warn "Download fehlgeschlagen — Codename '${codename}' oder ROCm-Version '${rocm_ver}' wird evtl. nicht angeboten."
    info "Passende Version findest du hier; danach z. B. ROCM_VERSION=6.x.y setzen:"
    info "  https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html"
    return 1
  fi
  $SUDO apt-get install -y -qq "/tmp/${amdgpu_deb}" \
    || { note_warn "amdgpu-install-Paket ließ sich nicht installieren."; return 1; }
  $SUDO apt-get update -qq || true

  info "Installiere amdgpu-Kernel-Treiber (DKMS) — das dauert ein paar Minuten…"
  if ! $SUDO apt-get install -y amdgpu-dkms; then
    note_warn "Installation von amdgpu-dkms fehlgeschlagen. Log oben prüfen."
    return 1
  fi
  ok "amdgpu-Treiber installiert."

  # Gruppen sicherstellen und Modul laden
  $SUDO modprobe amdgpu 2>/dev/null || true
  if [ -e /dev/kfd ]; then
    ok "/dev/kfd ist jetzt vorhanden — GPU ist bereit."
    return 0
  fi
  note_warn "Der Treiber wurde installiert, /dev/kfd erscheint aber erst nach einem Neustart."
  info "Bitte neu starten und den Installer erneut ausführen:"
  info "  sudo reboot     # danach:  cd $ROOT_DIR && sudo ./install.sh"
  return 0
}

# ── Deinstallation ──────────────────────────────────────────────────────────
# $1 = "purge" entfernt zusätzlich alle Daten-Volumes (unwiderruflich).
do_uninstall() {
  local purge="$1"

  printf '%s' "$c_bold"
  cat <<'BANNER'
╔══════════════════════════════════════════════════════╗
║   Self-Hosted AI Stack · Deinstallation              ║
╚══════════════════════════════════════════════════════╝
BANNER
  printf '%s' "$c_reset"

  command -v docker >/dev/null 2>&1 || die "Docker nicht gefunden — nichts zu tun."
  resolve_dc
  [ -n "$DC" ] || die "Docker Compose nicht gefunden."

  # Sicherheitsabfrage beim Purge
  if [ "$purge" = "purge" ] && [ "$ASSUME_YES" -ne 1 ]; then
    warn "PURGE entfernt ALLE Daten: geladene Modelle, Chats (Open WebUI), Datenbank und .env."
    printf '%sTippe zum Bestätigen »loeschen«: %s' "$c_bold" "$c_reset"
    read -r reply || reply=""
    [ "$reply" = "loeschen" ] || die "Abgebrochen — nichts wurde entfernt."
  fi

  local down_args=""
  [ "$purge" = "purge" ] && down_args="-v"

  # Beide Stacks herunterfahren (soweit die Compose-Dateien vorhanden sind).
  for f in docker-compose.rocm.yml docker-compose.yml; do
    if [ -f "$ROOT_DIR/$f" ]; then
      info "Fahre Stack herunter: $f"
      # shellcheck disable=SC2086
      (cd "$ROOT_DIR" && $DC -f "$f" down $down_args --remove-orphans 2>/dev/null) || true
    fi
  done

  # Übrig gebliebene Container (auch aus manuellem 'docker run') gezielt entfernen.
  local containers="ollama open-webui anythingllm litellm litellm-db db mcp \
sandbox-mcp mcpo vault-bridge embeddings whisper whisper-live kokoro docling ai-stack-init \
ai-stack-dashboard ai-stack-caddy"
  info "Entferne evtl. verbliebene Container…"
  for c in $containers; do
    docker rm -f "$c" >/dev/null 2>&1 && ok "Container entfernt: $c" || true
  done

  if [ "$purge" = "purge" ]; then
    # Bekannte Volumes beider Stacks (alte + neue Namen) löschen.
    local volumes="ollama-data ollama-shared litellm-data litellm-db litellm-shared \
ai-stack-shared open-webui-data anythingllm-data embeddings-data whisper-data \
whisper-live-data kokoro-data mcp-data mcp-shared vault-data vault-bridge-data \
docling-data caddy-data caddy-config"
    info "Lösche Daten-Volumes…"
    for v in $volumes; do
      docker volume rm "$v" >/dev/null 2>&1 && ok "Volume gelöscht: $v" || true
    done

    if [ -f "$ROOT_DIR/.env" ]; then
      rm -f "$ROOT_DIR/.env" && ok ".env entfernt."
    fi
    if [ -f "$ROOT_DIR/mcpo/config.json" ]; then
      rm -f "$ROOT_DIR/mcpo/config.json" && ok "mcpo/config.json entfernt (enthielt den MCP-API-Key)."
    fi
    warn "Firewall-Regeln (ufw) wurden NICHT verändert. Bei Bedarf manuell entfernen:"
    printf '    %s ufw status numbered\n' "${SUDO:-sudo}"
  else
    ok "Container/Netzwerke entfernt. Daten-Volumes und .env bleiben erhalten."
    info "Alles inkl. Daten entfernen:  ${SUDO:-sudo} ./install.sh --purge"
  fi

  step "Deinstallation abgeschlossen."
  exit 0
}

case "$MODE" in
  uninstall) do_uninstall "keep" ;;
  purge)     do_uninstall "purge" ;;
esac

printf '%s' "$c_bold"
cat <<'BANNER'
╔══════════════════════════════════════════════════════╗
║   Self-Hosted AI Stack · AMD ROCm Installer          ║
║   Ollama · Open WebUI · LiteLLM · Dashboard          ║
╚══════════════════════════════════════════════════════╝
BANNER
printf '%s' "$c_reset"

# ════════════════════════════════════════════════════════════════════════════
step "1/8 · System prüfen"

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
step "2/8 · AMD-GPU / ROCm prüfen"

GPU_OK=1
if lspci 2>/dev/null | grep -iE 'VGA|Display|3D' | grep -iq 'AMD\|ATI'; then
  ok "AMD-GPU erkannt: $(lspci 2>/dev/null | grep -iE 'VGA|Display|3D' | grep -i 'AMD\|ATI' | head -1 | cut -d: -f3- | sed 's/^ *//')"
else
  note_warn "Keine AMD-GPU über lspci erkannt (evtl. lspci fehlt)."; GPU_OK=0
fi

if lsmod 2>/dev/null | grep -q '^amdgpu' || [ -d /sys/module/amdgpu ]; then
  ok "amdgpu-Treiber aktiv (als Modul oder fest im Kernel eingebaut)."
else
  note_warn "amdgpu-Treiber nicht gefunden — GPU-Beschleunigung geht dann evtl. nicht."; GPU_OK=0
fi

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

if [ "$GPU_OK" -eq 1 ]; then
  ok "ROCm-Voraussetzungen erfüllt."
fi

# Treiber fehlt? Automatische Installation anbieten/durchführen.
# Harter Indikator ist /dev/kfd. --install-drivers erzwingt den Versuch.
if [ "$CHECK_ONLY" -eq 0 ] && [ "$INSTALL_AMD_DRIVERS" != "no" ]; then
  need_drivers=0
  [ ! -e /dev/kfd ] && need_drivers=1
  do_drv=0
  if [ "$INSTALL_AMD_DRIVERS" = "yes" ]; then
    do_drv=1
  elif [ "$need_drivers" -eq 1 ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then
      do_drv=1
    else
      printf '%sAMD-Kernel-Treiber (amdgpu-dkms) jetzt automatisch installieren? [j/N] %s' "$c_bold" "$c_reset"
      read -r drv_reply || drv_reply=""
      case "$drv_reply" in j|J|y|Y|ja|Ja|JA) do_drv=1 ;; esac
    fi
  fi

  if [ "$do_drv" -eq 1 ]; then
    step "AMD-Treiber installieren"
    if install_amd_drivers; then
      # Nach erfolgreicher Installation GIDs/Gruppen und /dev/kfd neu bewerten
      VIDEO_GID="$(getent group video 2>/dev/null | cut -d: -f3 || true)"; VIDEO_GID="${VIDEO_GID:-44}"
      RENDER_GID="$(getent group render 2>/dev/null | cut -d: -f3 || true)"; RENDER_GID="${RENDER_GID:-993}"
      for grp in video render; do
        if getent group "$grp" >/dev/null 2>&1 && ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
          $SUDO usermod -aG "$grp" "$TARGET_USER" 2>/dev/null || true
        fi
      done
      [ -e /dev/kfd ] && GPU_OK=1
    fi
  fi
fi

if [ "$GPU_OK" -ne 1 ]; then
  note_warn "ROCm nicht vollständig — der Stack startet trotzdem, nutzt dann aber die CPU."
  info "Treiber später nachrüsten: sudo ./install.sh --install-drivers"
fi

# ════════════════════════════════════════════════════════════════════════════
step "3/8 · Docker prüfen"

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
step "4/8 · Firewall (Modus: ${FIREWALL_MODE})"

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
    # WICHTIG für Docker: ufw setzt die FORWARD-Policy sonst auf DROP und kappt
    # damit den Container-Egress (Container kommen nicht mehr ins Internet ->
    # 'ollama pull' läuft in "i/o timeout"). Routing erlauben; der Ingress-
    # Schutz über die ufw-Regeln bleibt davon unberührt.
    if $SUDO ufw default allow routed >/dev/null 2>&1; then
      ok "ufw: Routing/Forward erlaubt (Docker-Container behalten Internetzugang)."
    else
      note_warn "Konnte ufw-Forward-Policy nicht setzen — Container-Internetzugang ggf. prüfen."
    fi
    # Zusätzlich, falls vorhanden, die Konfigdatei absichern (harmlos, wenn sie fehlt).
    [ -f /etc/default/ufw ] && $SUDO sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw 2>/dev/null || true
    if [ "$FIREWALL_MODE" = "lan" ]; then
      for p in "$PORT_WEBUI" "$PORT_LITELLM" "$PORT_DASHBOARD" "$PORT_VAULT_BRIDGE"; do
        $SUDO ufw allow from "$LAN_SUBNET" to any port "$p" proto tcp >/dev/null 2>&1 || true
      done
      ok "Firewall: SSH offen; Ports ${PORT_WEBUI}/${PORT_LITELLM}/${PORT_DASHBOARD}/${PORT_VAULT_BRIDGE} nur aus ${LAN_SUBNET}."
    else
      for p in "$PORT_WEBUI" "$PORT_LITELLM" "$PORT_DASHBOARD" "$PORT_VAULT_BRIDGE"; do
        $SUDO ufw allow "$p"/tcp >/dev/null 2>&1 || true
      done
      note_warn "Firewall: Ports ${PORT_WEBUI}/${PORT_LITELLM}/${PORT_DASHBOARD}/${PORT_VAULT_BRIDGE} für ALLE offen (nur mit HTTPS davor empfohlen)."
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
step "5/8 · Konfiguration schreiben (.env)"

# Zufalls-String. Wichtig: '|| true' fängt den SIGPIPE von 'tr' ab (head schließt
# die Pipe früh), sonst würde 'set -o pipefail' + 'set -e' das Skript abbrechen.
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${1:-32}" || true; }

if [ -f .env ]; then
  info "Bestehende .env gefunden — behalte vorhandene Secrets."
  # shellcheck disable=SC1091
  set -a; . ./.env; set +a
fi
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(rand 32)}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-$(rand 40)}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(rand 40)}"

# Host-MTU der Standardroute ermitteln und die Container-MTU daran anpassen.
# Verhindert TLS-Timeouts ("i/o timeout") aus Containern hinter VPN/Cloud-Overlays.
DEFAULT_DEV="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
HOST_MTU=""
[ -n "$DEFAULT_DEV" ] && HOST_MTU="$(cat "/sys/class/net/${DEFAULT_DEV}/mtu" 2>/dev/null || true)"
DOCKER_MTU="${DOCKER_MTU:-${HOST_MTU:-1500}}"
if [ "${DOCKER_MTU:-1500}" -lt 1500 ] 2>/dev/null; then
  info "Host-MTU ${DOCKER_MTU} (auf ${DEFAULT_DEV}) — setze Container-MTU passend (verhindert TLS-Timeouts)."
else
  info "Host-MTU: ${DOCKER_MTU:-1500} (Standard)."
fi

cat > .env <<EOF
# Automatisch erzeugt von install.sh — enthält Secrets, nicht committen!
COMPOSE_FILE=${COMPOSE_FILE}

# Standardmodell (mit einer Zeile änderbar). FALLBACK_MODEL wird gezogen,
# falls DEFAULT_MODEL (noch) nicht in der Ollama-Bibliothek liegt.
DEFAULT_MODEL=${DEFAULT_MODEL}
FALLBACK_MODEL=${FALLBACK_MODEL}

# AMD-GPU / ROCm (Strix Halo = gfx1151)
HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}
VIDEO_GID=${VIDEO_GID}
RENDER_GID=${RENDER_GID}
OLLAMA_KEEP_ALIVE=30m

# Docker-Netzwerk-MTU (an Host-MTU angepasst; verhindert TLS-Timeouts im Container)
DOCKER_MTU=${DOCKER_MTU}

# Ports
PORT_WEBUI=${PORT_WEBUI}
PORT_LITELLM=${PORT_LITELLM}
PORT_DASHBOARD=${PORT_DASHBOARD}
PORT_OLLAMA=11434
PORT_WHISPER=9000
PORT_EMBEDDINGS=8000
PORT_VAULT_BRIDGE=8700

# Code-Sandbox (run_python/run_shell fürs LLM; Wegwerf-Container pro Aufruf,
# siehe README "Code-Sandbox"). SANDBOX_NETWORK=none = kein Internetzugriff
# aus dem ausgeführten Code (Standard, sicherer). Docker-Socket nötig — falls
# unerwünscht, den sandbox-mcp-Dienst aus docker-compose.rocm.yml entfernen.
SANDBOX_IMAGE=python:3.12-slim
SANDBOX_DEFAULT_TIMEOUT=15
SANDBOX_MAX_TIMEOUT=60
SANDBOX_MEM_LIMIT=256m
SANDBOX_NETWORK=none

# Vault-Bridge (Obsidian-Vault auf Nextcloud <-> MCP-Gateway-Dateisystem-
# Werkzeug, siehe README "Vault-Bridge"). Verbindung wird über die eigene
# Web-Oberfläche (Port PORT_VAULT_BRIDGE) hergestellt, nicht hier — hier nur
# der Port. MCP_SERVERS/MCP_FILESYSTEM_DIRS unten steuern, welche MCP-
# Gateway-Werkzeuge aktiv sind und welche Verzeichnisse sie sehen.
MCP_SERVERS=fetch,filesystem
MCP_FILESYSTEM_DIRS=/vault

# Secrets
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}

# Firewall
LAN_SUBNET=${LAN_SUBNET}
EOF
chmod 600 .env
ok ".env geschrieben (Rechte 600)."

# mcpo/config.json muss vor dem ersten Start als echte DATEI existieren, sonst
# legt Docker beim Bind-Mount einer fehlenden Datei ein leeres Verzeichnis an
# und mcpo crasht dauerhaft mit "Is a directory". Ein evtl. von einem früheren
# Start fälschlich angelegtes Verzeichnis wird zuerst entfernt (nur falls leer
# — sonst lieber melden statt Daten zu löschen). Platzhalter-Key wird gleich
# von scripts/wire-mcp.sh mit dem echten ersetzt.
if [ -d mcpo/config.json ]; then
  rmdir mcpo/config.json 2>/dev/null \
    || note_warn "mcpo/config.json ist ein nicht-leeres Verzeichnis — bitte manuell prüfen: ls -la mcpo/config.json"
fi
if [ -f mcpo/config.template.json ] && [ ! -e mcpo/config.json ]; then
  cp mcpo/config.template.json mcpo/config.json
fi

# ════════════════════════════════════════════════════════════════════════════
step "6/8 · Stack starten"

info "Ziehe Images, baue lokale Dienste (sandbox-mcp, vault-bridge) und starte Container (kann beim ersten Mal dauern)…"
$DC -f "$COMPOSE_FILE" up -d --build

info "Warte, bis Ollama bereit ist…"
for i in $(seq 1 60); do
  if docker exec ollama ollama list >/dev/null 2>&1; then ok "Ollama ist bereit."; break; fi
  sleep 3
  [ "$i" -eq 60 ] && note_warn "Ollama wurde nicht rechtzeitig bereit — prüfe 'docker logs ollama'."
done

info "Lade Standardmodell: ${DEFAULT_MODEL} (das dauert je nach Größe)…"
if docker exec ollama ollama pull "$DEFAULT_MODEL"; then
  ok "Modell ${DEFAULT_MODEL} geladen."
elif [ -n "$FALLBACK_MODEL" ] && [ "$FALLBACK_MODEL" != "$DEFAULT_MODEL" ]; then
  note_warn "'${DEFAULT_MODEL}' ließ sich nicht laden (evtl. noch nicht in der Ollama-Bibliothek)."
  info "Nutze Fallback-Modell: ${FALLBACK_MODEL}…"
  if docker exec ollama ollama pull "$FALLBACK_MODEL"; then
    ok "Fallback-Modell ${FALLBACK_MODEL} geladen."
    info "Sobald '${DEFAULT_MODEL}' verfügbar ist: DEFAULT_MODEL in .env anpassen und 'docker exec ollama ollama pull ${DEFAULT_MODEL}'."
  else
    note_warn "Auch das Fallback-Modell ließ sich nicht laden. Später manuell: docker exec ollama ollama pull <modell>"
  fi
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
step "7/8 · MCP Gateway mit LiteLLM verdrahten"

bash "$ROOT_DIR/scripts/wire-mcp.sh" || note_warn "MCP-Wiring unvollständig — später erneut ausführen: ./scripts/wire-mcp.sh"

# ════════════════════════════════════════════════════════════════════════════
step "8/8 · Modelle bei LiteLLM eintragen"

# HTTP-Check ohne curl-Abhängigkeit (Host hat evtl. kein curl, aber python3).
http_ok() {
  if command -v curl >/dev/null 2>&1; then
    curl -sf "$1" >/dev/null 2>&1
  else
    python3 - "$1" <<'PY' >/dev/null 2>&1
import sys, urllib.request
urllib.request.urlopen(sys.argv[1], timeout=3)
PY
  fi
}

info "Warte auf LiteLLM…"
for i in $(seq 1 40); do
  if http_ok "http://localhost:${PORT_LITELLM}/health/liveliness"; then ok "LiteLLM ist bereit."; break; fi
  sleep 3
done
bash "$ROOT_DIR/scripts/sync-ollama-models.sh" || note_warn "Modell-Sync unvollständig — später erneut ausführen: ./scripts/sync-ollama-models.sh"

# ════════════════════════════════════════════════════════════════════════════
IP="$(ip -o -f inet addr show scope global 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1 || true)"
IP="${IP:-<server-ip>}"

step "Fertig! 🎉"
cat <<EOF

  ${c_bold}Nützliche Befehle:${c_reset}
    Zugangsdaten   ./scripts/show-credentials.sh
    Status         ${DC} -f ${COMPOSE_FILE} ps
    Logs           ${DC} -f ${COMPOSE_FILE} logs -f <dienst>
    Modell laden   docker exec ollama ollama pull <modell>
    Modelle syncen ./scripts/sync-ollama-models.sh
    MCP neu verdrahten ./scripts/wire-mcp.sh
    Stoppen        ${DC} -f ${COMPOSE_FILE} down

EOF
bash "$ROOT_DIR/scripts/show-credentials.sh" || true
echo
[ "$WARNINGS" -gt 0 ] && warn "$WARNINGS Warnung(en) während der Installation — bitte oben prüfen."
ok "Viel Spaß mit deinem privaten KI-Stack!"
