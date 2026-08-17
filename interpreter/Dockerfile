# Open Interpreter als CLI im Container.
#
# Warum im Container und nicht auf dem Host: Open Interpreter führt Code aus,
# den das Modell schreibt — auf dem Host hieße das Zugriff auf alles, was dein
# Benutzer darf. Im Container sieht es nur, was eingehängt ist (standardmäßig
# nur /work). Und es ist mit einem 'docker rmi' wieder komplett weg, statt
# hundert Python-Pakete im System zu hinterlassen.
FROM python:3.12-slim

ARG OPEN_INTERPRETER_VERSION=0.4.3

# git/curl: Open Interpreter schlägt dem Modell oft Git- und Netz-Aufrufe vor.
# build-essential: einige Abhängigkeiten bringen keine fertigen Wheels mit.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates build-essential \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "open-interpreter==${OPEN_INTERPRETER_VERSION}"

# Nicht als root arbeiten. /work ist der einzige Ort, an den geschrieben wird —
# und liegt als Volume auf dem Host, damit Ergebnisse den Container überleben.
RUN useradd --create-home --uid 1000 oi \
 && mkdir -p /work /home/oi/.config/open-interpreter \
 && chown -R oi:oi /work /home/oi

COPY entrypoint.sh /usr/local/bin/oi-entrypoint
RUN chmod 0755 /usr/local/bin/oi-entrypoint

USER oi
WORKDIR /work
ENV HOME=/home/oi \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

ENTRYPOINT ["/usr/local/bin/oi-entrypoint"]
