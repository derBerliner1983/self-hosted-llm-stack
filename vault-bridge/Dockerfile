FROM python:3.12-slim

# rclone: synct das Nextcloud-WebDAV-Verzeichnis (Obsidian-Vault) auf einen
# lokalen Docker-Volume-Pfad. curl nur für den Healthcheck.
RUN apt-get update \
    && apt-get install -y --no-install-recommends rclone curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY app.py .
COPY index.html .

ENV VAULT_BRIDGE_PORT=8080
EXPOSE 8080

CMD ["python", "app.py"]
