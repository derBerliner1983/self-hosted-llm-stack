# Mehrsprachiges Runner-Image für die Code-Sandbox.
#
# WICHTIG: Das ist NICHT das Image des sandbox-mcp-Dienstes selbst (das ist
# ./Dockerfile), sondern das Image, aus dem die Sandbox pro Werkzeugaufruf
# einen frischen Wegwerf-Container startet. Der Standard ist
# "python:3.12-slim" — also nur Python und Shell. Dieses Image hier bringt
# zusätzlich die gängigen Compiler/Laufzeiten mit.
#
# Bauen und aktivieren (siehe README, "Mehr Sprachen in der Sandbox"):
#
#   docker build -f sandbox-mcp/runner-multilang.Dockerfile \
#     -t ai-stack-sandbox-runner:multilang sandbox-mcp/
#
#   # optional mit PowerShell (pwsh), kostet ~200 MB extra:
#   docker build --build-arg WITH_POWERSHELL=1 \
#     -f sandbox-mcp/runner-multilang.Dockerfile \
#     -t ai-stack-sandbox-runner:multilang sandbox-mcp/
#
#   # in der .env:
#   SANDBOX_IMAGE=ai-stack-sandbox-runner:multilang
#   SANDBOX_MEM_LIMIT=2g
#   SANDBOX_TMPFS_SIZE=1g
#   SANDBOX_DEFAULT_TIMEOUT=60
#   SANDBOX_MAX_TIMEOUT=180
#
#   docker compose -f docker-compose.rocm.yml up -d sandbox-mcp
#
# Die höheren Limits sind nicht optional: javac/go build/g++ scheitern an den
# Standardwerten (256 MB RAM, 64 MB /tmp, 15 s) zuverlässig.

FROM python:3.12-slim

# PowerShell mitinstallieren? Standard aus, weil es ~200 MB kostet und aus
# einer zusätzlichen Paketquelle (Microsoft) kommt. Anschalten mit:
#   docker build --build-arg WITH_POWERSHELL=1 ...
ARG WITH_POWERSHELL=0

# Ein einziger apt-Lauf, damit keine Zwischenschicht den Paketindex behält.
#   build-essential  → gcc, g++, make
#   default-jdk      → javac + java (JDK 17 auf Debian bookworm)
#   golang-go        → go build / go run
#   nodejs, npm      → node
#   Kleinkram        → git/curl für Skripte, die das erwarten; jq für JSON
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        default-jdk \
        golang-go \
        nodejs \
        npm \
        git \
        curl \
        jq \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# PowerShell (pwsh) aus Microsofts Paketquelle — nur bei WITH_POWERSHELL=1.
# Nicht in den Debian-Quellen enthalten, daher der Extraschritt. Läuft auf
# Linux vollwertig; Windows-spezifische Cmdlets (Registry, WMI, AD, ...)
# gibt es dort naturgemäß trotzdem nicht.
RUN if [ "$WITH_POWERSHELL" = "1" ]; then \
        set -eux; \
        apt-get update; \
        apt-get install -y --no-install-recommends gnupg apt-transport-https; \
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor -o /etc/apt/trusted.gpg.d/microsoft.gpg; \
        echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
            > /etc/apt/sources.list.d/microsoft.list; \
        apt-get update; \
        apt-get install -y --no-install-recommends powershell; \
        apt-get purge -y gnupg apt-transport-https; \
        apt-get autoremove -y; \
        rm -rf /var/lib/apt/lists/*; \
        pwsh --version; \
    fi

# Compiler und Laufzeiten legen ihre Caches sonst unter $HOME an — das
# scheitert, weil die Sandbox als "nobody" mit read-only-Dateisystem läuft
# und nur /tmp beschreibbar ist. Alles dorthin umlenken.
ENV HOME=/tmp \
    GOCACHE=/tmp/.cache/go-build \
    GOPATH=/tmp/go \
    GOFLAGS=-modcacherw \
    npm_config_cache=/tmp/.npm \
    XDG_CACHE_HOME=/tmp/.cache \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    POWERSHELL_UPDATECHECK=Off \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /tmp
