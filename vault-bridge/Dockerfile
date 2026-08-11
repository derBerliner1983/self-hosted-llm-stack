FROM python:3.12-slim

# rclone: synct das Nextcloud-WebDAV-Verzeichnis (Obsidian-Vault) auf einen
# lokalen Docker-Volume-Pfad. curl auch für den offiziellen rclone-Installer.
#
# Bewusst NICHT aus den Debian-Paketquellen (apt) installiert - das dort
# gepackte rclone ist meist veraltet und markiert "bisync" (Zwei-Wege-Sync,
# siehe README) noch als experimentell mit stark eingeschränktem Flag-Satz
# (kein --fast-list, --conflict-resolve, --resilient, ...). Stattdessen der
# offizielle rclone-Installer für eine aktuelle, stabile Version.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && curl -fsSL https://rclone.org/install.sh | bash \
    && apt-get purge -y unzip \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY app.py .
COPY index.html .

ENV VAULT_BRIDGE_PORT=8080
EXPOSE 8080

CMD ["python", "app.py"]
