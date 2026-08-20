# Excalidraw-Diagramme als MCP-Werkzeuge.
#
# Anders als android-mcp/sandbox-mcp braucht dieser Dienst weder ein SDK
# noch den Docker-Socket - er schreibt nur .excalidraw-Dateien (offenes
# JSON-Dateiformat) in sein eigenes Arbeitsverzeichnis und kopiert sie auf
# Wunsch nach /exchange. Deshalb das schlanke Basis-Image, kein root nötig.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

# /diagrams kommt im Betrieb aus einem benannten Volume (überlebt
# Neustarts), /exchange ist dasselbe geteilte Volume wie bei
# exchange-bridge/android-mcp/mcp - hier nur als Kopierziel für
# export_diagram(), kein Werkzeug liest von dort.
RUN mkdir -p /diagrams

ENV FASTMCP_HOST=0.0.0.0 \
    FASTMCP_PORT=8000 \
    EXCALIDRAW_WORKSPACE=/diagrams \
    EXCALIDRAW_EXCHANGE_DIR=/exchange

EXPOSE 8000

CMD ["python3", "server.py"]
