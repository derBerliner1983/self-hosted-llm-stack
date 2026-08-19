FROM python:3.12-slim

# Keine Zusatzabhaengigkeiten - reine Python-Standardbibliothek, derselbe
# minimalistische Stil wie dashboard/ und vault-bridge/.

WORKDIR /app
COPY app.py .
COPY index.html .

ENV EXCHANGE_BRIDGE_PORT=8080
EXPOSE 8080

CMD ["python", "app.py"]
