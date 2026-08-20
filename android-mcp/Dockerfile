# Android-Build-Umgebung als MCP-Dienst.
#
# Bewusst anders gebaut als sandbox-mcp: Dort startet jeder Aufruf einen
# frischen Wegwerf-Container ohne Netzwerk. Android-Builds brauchen das
# Gegenteil - Netzwerk (Gradle lädt Abhängigkeiten), persistenten Cache
# (sonst lädt jeder Build alles neu) und Laufzeiten in Minuten statt
# Sekunden. Deshalb laufen die Builds hier direkt im Dienst-Container.
# Angenehmer Nebeneffekt: kein Docker-Socket nötig.

FROM eclipse-temurin:21-jdk-noble

# Version der Android-Kommandozeilen-Werkzeuge. Die "_latest"-Datei ändert
# sich, ohne dass sich der Dateiname ändert - deshalb hier die konkrete
# Build-Nummer, damit Neubauten reproduzierbar bleiben. Aktuelle Nummer:
# https://developer.android.com/studio#command-line-tools-only
ARG CMDLINE_TOOLS_VERSION=11076708
# Welche SDK-Pakete installiert werden. Bewusst schlank gehalten - weitere
# lassen sich zur Laufzeit über das sdkmanager-Werkzeug nachinstallieren.
ARG ANDROID_PLATFORM=android-34
ARG BUILD_TOOLS_VERSION=34.0.0
# Standalone-Gradle NUR zum Erzeugen des Wrappers (server.py: create_project
# ruft "gradle wrapper --gradle-version ..." auf, um gradlew/gradle-wrapper.jar
# in ein neues Projekt zu legen). Für die eigentlichen Builds benutzt jedes
# Projekt danach seinen eigenen Wrapper - der lädt sich beim ersten Aufruf
# die in ANDROID_GRADLE_VERSION (server.py) gewünschte Version selbst nach.
# Muss NICHT exakt zur Wrapper-Zielversion passen, "gradle wrapper" kann
# einen Wrapper für eine andere Version erzeugen als die, mit der es selbst
# läuft - hier trotzdem gleich gehalten, um genau das zu vermeiden.
ARG GRADLE_VERSION=8.7

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/gradle \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        unzip \
        curl \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Android-SDK einrichten. sdkmanager erwartet die Werkzeuge zwingend unter
# cmdline-tools/latest/ - liegen sie direkt in cmdline-tools/, bricht er mit
# einer wenig hilfreichen Meldung ab.
RUN set -eux; \
    mkdir -p "$ANDROID_HOME/cmdline-tools"; \
    curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"; \
    unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools; \
    mv /tmp/cmdline-tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"; \
    rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools

ENV PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Standalone Gradle installieren. Ohne dieses Paket gibt es im Image
# überhaupt kein "gradle"-Kommando - create_project() in server.py, das
# damit den Wrapper eines neuen Projekts erzeugt, schlägt dann fehl
# (Python bekommt ein OSError, weil "gradle" nicht im PATH steht). Neue
# Projekte landeten dadurch bislang OHNE gradlew im Arbeitsbereich, und
# das anschließende gradle()-Werkzeug meldete "Weder ein Gradle-Wrapper im
# Projekt noch ein globales gradle gefunden" - kein Bug im Wrapper-Aufruf
# selbst, sondern schlicht ein fehlendes Gradle im Image.
RUN set -eux; \
    curl -fsSL -o /tmp/gradle.zip \
        "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"; \
    unzip -q /tmp/gradle.zip -d /opt; \
    mv "/opt/gradle-${GRADLE_VERSION}" /opt/gradle; \
    rm -f /tmp/gradle.zip

ENV PATH="/opt/gradle/bin:$PATH"

# Lizenzen annehmen und die Basispakete holen. Ohne angenommene Lizenzen
# bricht jeder Gradle-Build mit "You have not accepted the license
# agreements" ab.
RUN set -eux; \
    yes | sdkmanager --licenses > /dev/null; \
    sdkmanager --install \
        "platform-tools" \
        "platforms;${ANDROID_PLATFORM}" \
        "build-tools;${BUILD_TOOLS_VERSION}" \
        > /dev/null; \
    sdkmanager --list_installed

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

COPY server.py .

# /workspace hält die Projekte, /gradle den Abhängigkeits-Cache - beide
# kommen im Betrieb aus benannten Volumes, damit sie Neustarts überleben.
RUN mkdir -p /workspace /gradle

ENV FASTMCP_HOST=0.0.0.0 \
    FASTMCP_PORT=8000 \
    ANDROID_WORKSPACE=/workspace

EXPOSE 8000

CMD ["python3", "server.py"]
