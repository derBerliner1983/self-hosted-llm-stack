# Sicherheit & Fernzugriff

Firewall, Reverse-Proxy mit Login/MFA und was ins Internet darf.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/security.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Excalidraw](excalidraw.md) · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · **Sicherheit & Fernzugriff** · [Weitere Stacks](weitere-stacks.md)

---

## Ins Internet gerichtete Bereitstellungen

Standardmäßig lauschen alle Dienste über einfaches HTTP. Für ins Internet gerichtete Bereitstellungen nutze das mitgelieferte Caddy-Overlay, um automatisches HTTPS hinzuzufügen. Im Proxy-Modus ist Caddy der einzige öffentliche Listener auf den Ports `80` und `443`; die direkten AnythingLLM- und LiteLLM-Ports werden auf `127.0.0.1` neu gebunden.

Voraussetzungen:

- Docker Compose `2.24.4+` (erforderlich für die Port-Überschreibung des Proxy-Overlays)
- Ein DNS-`A`/`AAAA`-Eintrag für deine Domain, der auf diesen Server zeigt
- Eingehende `80/tcp`, `443/tcp` und idealerweise `443/udp` in deiner Firewall/Sicherheitsgruppe geöffnet
- Kein anderer Dienst nutzt bereits die Ports `80` oder `443` auf dem Host

**CPU-Stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

**CUDA-Stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.cuda.yml -f docker-compose.proxy.yml up -d
```

Öffne `https://chat.example.com` (ersetze durch deine `DOMAIN`), um auf AnythingLLM zuzugreifen. Im Proxy-Modus bleiben `http://127.0.0.1:3001` und `http://127.0.0.1:4000/ui` auf dem Host verfügbar, aber die direkten Ports `3001` und `4000` sind von außerhalb des Servers nicht erreichbar.

Die Standard-Compose-Dateien veröffentlichen LiteLLM auf Port `4000`. Das Proxy-Overlay ändert diesen direkten Port auf localhost-only, und die mitgelieferte Caddyfile leitet standardmäßig nur AnythingLLM weiter. Das Auskommentieren des optionalen LiteLLM-Hostname-Blocks stellt LiteLLM über Caddy bereit, halte daher den LiteLLM-Masterschlüssel geheim.

Fehlerbehebung:

```bash
docker logs ai-stack-caddy
# Nutze dieselben -f-Dateien, mit denen du den Stack gestartet hast
docker compose -f docker-compose.yml -f docker-compose.proxy.yml ps
```

Wenn Caddy eine unbekannte `request_body`-Direktive meldet, lade das aktuelle `caddy:2`-Image herunter und starte das Overlay neu.

Für ältere Docker-Compose-Versionen oder Podman nutze stattdessen einen host-basierten Reverse-Proxy: Binde die direkten HTTP-Ports in der Compose-Datei an localhost (zum Beispiel `"127.0.0.1:3001:3001/tcp"` und `"127.0.0.1:4000:4000/tcp"`) und leite an diese localhost-Ports weiter. Für stack-spezifische Caddy- und nginx-Beispiele siehe den [Abschnitt zum manuellen Reverse-Proxy für die Chat-UI](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/chat-ui).

Wenn du Dienste ins Internet stellst, nutze wo vorhanden die erzeugten API-Schlüssel. Setze für bestehende Bereitstellungen ohne Schlüssel die API-Schlüssel über die entsprechenden env-Dateien, bevor du diese Dienste veröffentlichst.
