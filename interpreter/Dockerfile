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

# setuptools muss ausdrücklich mit: seit Python 3.12 bringt ensurepip es nicht
# mehr mit, das Basis-Image hat also nur pip. Open Interpreter importiert aber
# in core/utils/system_debug_info.py noch pkg_resources — das steckt in
# setuptools. Ohne diese Zeile startet 'interpreter' gar nicht:
#   ModuleNotFoundError: No module named 'pkg_resources'
# Die Grenze <81 ist trotzdem Absicht: ab 81 aendert sich pkg_resources'
# Verhalten nochmal deutlicher. Die Deprecation-Warnung selbst bleibt davon
# unberuehrt - die kommt unabhaengig von der genauen Version und wird darum
# im Entrypoint gezielt ausgeblendet (an einer echten Installation
# beobachtet: <81 haelt sie NICHT fern, anders als hier zuvor vermerkt).
# Beides in einem Aufruf, damit pip die Grenze bei der Auflösung kennt — in
# zwei Schritten könnte die zweite Installation setuptools wieder hochziehen.
RUN pip install --no-cache-dir \
      "setuptools<81" \
      "open-interpreter==${OPEN_INTERPRETER_VERSION}"

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

# Rauchprobe beim Bauen statt beim ersten Start: genau dieser Import ist über
# das fehlende pkg_resources gestolpert. Schlägt er fehl, gibt es kein Image —
# besser als ein Abbruch, wenn du das Werkzeug gerade benutzen willst.
RUN python -c "from interpreter.terminal_interface.start_terminal_interface import main"

ENTRYPOINT ["/usr/local/bin/oi-entrypoint"]
