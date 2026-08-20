# Excalidraw-Diagramme als MCP-Werkzeuge.
#
# Zweistufiger Bau:
#   1. "jsbuild" (Node) bündelt Excalidraws eigenen exportToBlob()-Renderer
#      (siehe render/entry.js) einmalig zu einer einzigen bundle.js - nur
#      dafür wird Node gebraucht, es landet nichts davon im fertigen Image.
#   2. Die eigentliche Stufe basiert auf dem offiziellen Playwright-Image
#      (Python + Chromium + alle Systemabhängigkeiten schon vorinstalliert -
#      das von Hand nachzuziehen ist auf Debian/Ubuntu erfahrungsgemäß
#      fehleranfällig, Playwright pflegt genau diese Kombination selbst).
#
# export_png() (server.py) lädt die gebündelte bundle.js in einem headless
# Chromium und ruft darin denselben Renderer auf, den auch das echte
# Excalidraw im Browser benutzt - dieselbe Handschrift-Schrift, dieselben
# Formen, aber serverseitig und ohne externen Dienst zur Laufzeit.

# ── Stufe 1: JS-Bundle bauen ────────────────────────────────────────────
FROM node:22-slim AS jsbuild

WORKDIR /build

# Feste Versionen statt "latest" - reproduzierbare Bilder, kein
# überraschender Bruch durch ein neues Excalidraw-Release.
RUN npm install --no-audit --no-fund \
      react@18.3.1 \
      react-dom@18.3.1 \
      @excalidraw/excalidraw@0.18.1 \
      esbuild@0.28.2

COPY render/entry.js .

# CSS/Bild-Assets landen nicht im Bundle (nicht gebraucht - exportToBlob
# zeichnet direkt auf einen Canvas, keine sichtbare UI). Schriften bewusst
# NICHT als Data-URI einbetten (--loader:.woff2=dataurl würde das Bundle
# auf >13 MB aufblähen UND wird beim Rendern gar nicht genutzt - siehe
# harness.html/EXCALIDRAW_ASSET_PATH: Excalidraw lädt Schriften immer per
# fetch() zur Laufzeit, nie aus dem eigenen Bundle-Code). Stattdessen
# werden die echten Font-Dateien unten separat kopiert und über
# EXCALIDRAW_ASSET_PATH lokal ausgeliefert.
RUN npx esbuild entry.js --bundle --format=iife --platform=browser \
      --define:process.env.NODE_ENV='"production"' \
      --outfile=/render/bundle.js

COPY render/harness.html /render/harness.html

# Nur die Schriftdateien, kein restlicher npm-Ballast (node_modules bleibt
# in dieser Stufe zurück, wird nicht in die nächste kopiert).
RUN mkdir -p /render/fonts \
 && cp -r node_modules/@excalidraw/excalidraw/dist/prod/fonts/* /render/fonts/

# ── Stufe 2: eigentlicher Dienst ────────────────────────────────────────
FROM mcr.microsoft.com/playwright/python:v1.62.0-noble

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .
COPY --from=jsbuild /render /app/render

# /diagrams kommt im Betrieb aus einem benannten Volume (überlebt
# Neustarts), /exchange ist dasselbe geteilte Volume wie bei
# exchange-bridge/android-mcp/mcp - hier Kopierziel für export_diagram()
# und export_png().
RUN mkdir -p /diagrams

ENV FASTMCP_HOST=0.0.0.0 \
    FASTMCP_PORT=8000 \
    EXCALIDRAW_WORKSPACE=/diagrams \
    EXCALIDRAW_EXCHANGE_DIR=/exchange \
    EXCALIDRAW_RENDER_DIR=/app/render \
    EXCALIDRAW_RENDER_PORT=8934

EXPOSE 8000

CMD ["python3", "server.py"]
