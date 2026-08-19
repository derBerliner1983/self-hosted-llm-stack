# Betrieb & Wartung

Alltagsbefehle, Aktualisierung, Sicherung und Zugangsdaten.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/operations.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · **Betrieb & Wartung** · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Nützliche Befehle

```bash
./scripts/show-credentials.sh                                 # URLs, Master-Key, Passwörter
./scripts/wire-mcp.sh                                         # MCP Gateway (neu) mit LiteLLM + Open WebUI (mcpo) verdrahten
./scripts/restart-mcp.sh                                      # MCP-Dienste neu starten — mcpo automatisch zuletzt (gegen "MCP session is not available")
./scripts/restart-mcp.sh --build                              # ...zusätzlich vault-bridge und sandbox-mcp neu bauen (nach Code-Änderungen)
./scripts/diagnose-chat.sh <modell> ["nachricht"]             # Kaputte Antworten Schicht für Schicht eingrenzen (Ollama/LiteLLM/WebUI)
LITELLM_KEY_OVERRIDE=<key> ./scripts/diagnose-chat.sh <modell> # ...testweise mit einem LiteLLM-Virtual-Key statt dem Master-Key
docker compose -f docker-compose.rocm.yml ps                  # Status
docker compose -f docker-compose.rocm.yml logs -f open-webui  # Logs eines Dienstes
docker compose -f docker-compose.rocm.yml down                # Stoppen (Daten bleiben in Volumes)
```

## Images aktualisieren

Um alle Dienste auf die neuesten Versionen zu aktualisieren:

```bash
git pull
docker compose pull
docker compose up -d
./stack-check.sh
```

Führe nach dem Neustart des Stacks `./stack-check.sh` aus, um zu bestätigen, dass die Dienste und die erzeugte Verdrahtung der Zugangsdaten fehlerfrei sind.

`git pull` aktualisiert alle Projektdateien (einschließlich etwaiger Änderungen an den Compose-Dateien); `docker compose pull` aktualisiert die Dienst-Images. Wenn du `docker-compose.yml` angepasst hast, führt `git pull` Änderungen automatisch zusammen oder fordert dich auf, Konflikte in denselben Zeilen aufzulösen.

**Einmaliger Hinweis für ältere Installationen:** Wenn du ein AnythingLLM-Passwort vor dem `.env`-Persistenz-Fix gesetzt hast, kann die erste Neuerstellung des Containers nach dem Upgrade dieses Passwort löschen und AnythingLLM ungeschützt lassen. Öffne AnythingLLM nach dem Update sofort und bestätige, dass der Passwortschutz noch aktiviert ist. Falls nicht, setze ein neues Passwort unter **Settings → Security**. Zukünftige Container-Neuerstellungen bewahren es.

AnythingLLM ist auf ein stabiles Release-Tag statt auf `latest` gepinnt, weil das Upstream-`latest`-Image dem Master-Branch folgt. Wenn ein neueres AnythingLLM-Release verfügbar ist, sichere zuerst, aktualisiere das Tag in den Compose-Dateien und führe dann die obigen Befehle aus.

Deine Daten bleiben in den Docker-Volumes erhalten. **[Sichere](#sicherung-und-wiederherstellung) immer, bevor du ein Upgrade durchführst.**

## Sicherung und Wiederherstellung

Deine API-Schlüssel, Modelle und Konfiguration werden in Docker-Volumes gespeichert. Sichere sie vor einem Upgrade oder vor Änderungen:

```bash
# API-Schlüssel exportieren (während die Container laufen)
docker exec ollama ollama_manage --getkey
docker exec litellm litellm_manage --getkey
docker exec mcp mcp_manage --getkey
# Optionale Dienste; ignoriert, wenn der Container nicht aktiviert/laufend ist
docker exec whisper whisper_manage --getkey 2>/dev/null || true
docker exec whisper-live whisper_live_manage --getkey 2>/dev/null || true
docker exec kokoro kokoro_manage --getkey 2>/dev/null || true
docker exec embeddings embed_manage --getkey 2>/dev/null || true
docker exec docling docling_manage --getkey 2>/dev/null || true

# Alle Volumes sichern (stoppe zuerst die Dienste)
# Alle Container stoppen und entfernen (Daten bleiben in Docker-Volumes erhalten)
docker compose down
mkdir -p backups
for vol in ollama-data litellm-data litellm-db ai-stack-shared embeddings-data whisper-data whisper-live-data kokoro-data mcp-data docling-data anythingllm-data caddy-data caddy-config; do
  docker volume inspect "$vol" >/dev/null 2>&1 && \
    docker run --rm -v "${vol}:/source:ro" -v "$(pwd)/backups:/backup" \
      alpine tar czf "/backup/${vol}.tar.gz" -C /source .
done
```

**Hinweis:** Sichere `ai-stack-shared` zusammen mit `litellm-db`; neue Installationen speichern dort das erzeugte PostgreSQL-Passwort. Die Volumes `ollama-shared`, `mcp-shared` und `litellm-shared` sind kurzlebige Volumes zum Teilen von Schlüsseln und müssen nicht gesichert werden.

Anweisungen zur Wiederherstellung, Server-Migration und die vollständige Checkliste vor dem Upgrade findest du in der Anleitung zu [Sicherung und Wiederherstellung](../../docs/backup-restore.md).

## PostgreSQL-Zugangsdaten

Neue Docker-Compose-Installationen erzeugen automatisch ein zufälliges PostgreSQL-Passwort und speichern es im `ai-stack-shared`-Volume. Bestehende Standardinstallationen nutzen aus Kompatibilitätsgründen weiterhin das ältere `litellm`-Datenbankpasswort.

Wenn du das Datenbankpasswort zuvor angepasst hast, setze `LITELLM_POSTGRES_PASSWORD` in deiner Shell-Umgebung auf dieses aktuelle Passwort, bevor du `docker compose up -d` ausführst, oder behalte eine explizite `LITELLM_DATABASE_URL`-Überschreibung in `litellm.env`.

## Nutzungszählungen

Self-Hosted AI Stack nutzt anonyme, aggregierte Zählungen der Downloads von GitHub-Release-Assets, um die Nutzung zu verstehen und zukünftige Verbesserungen zu priorisieren. Es wird keine Telemetrie-Nutzlast gesendet und kein privater Collector verwendet.

Um die Nutzungszählungen beim Start des Stacks zu deaktivieren:

```bash
AI_STACK_DISABLE_USAGE_COUNTS=1 docker compose up -d
```

## Anpassung

Jeder Dienst kann über eine optionale env-Datei konfiguriert werden. Kopiere die Beispiel-env-Datei aus dem jeweiligen Repository, bearbeite sie und kommentiere den Volume-Mount in `docker-compose.yml` aus:

| Dienst | Env-Datei | Repository |
|---|---|---|
| Ollama | `ollama.env` | [docker-ollama](https://github.com/hwdsl2/docker-ollama) |
| LiteLLM | `litellm.env` | [docker-litellm](https://github.com/hwdsl2/docker-litellm) |
| Embeddings | `embed.env` | [docker-embeddings](https://github.com/hwdsl2/docker-embeddings) |
| Whisper | `whisper.env` | [docker-whisper](https://github.com/hwdsl2/docker-whisper) |
| WhisperLive | `whisper-live.env` | [docker-whisper-live](https://github.com/hwdsl2/docker-whisper-live) |
| Kokoro | `kokoro.env` | [docker-kokoro](https://github.com/hwdsl2/docker-kokoro) |
| MCP Gateway | `mcp.env` | [docker-mcp-gateway](https://github.com/hwdsl2/docker-mcp-gateway) |
| Docling | `docling.env` | [docker-docling](https://github.com/hwdsl2/docker-docling) |

AnythingLLM wird über seine Web-UI unter `http://<server-ip>:3001` konfiguriert. Du kannst den LLM-Anbieter, das Modell, die Embedding-Engine und andere Einstellungen unter **Settings** ändern. Weitere Details findest du in der [AnythingLLM-Dokumentation](https://docs.useanything.com/).

**Den Embeddings-Dienst des Stacks nutzen (optional).** Standardmäßig bettet AnythingLLM Dokumente prozessintern mit seinem mitgelieferten MiniLM-Modell ein und speichert die Vektoren in seiner eigenen LanceDB. Um stattdessen den [Embeddings](https://github.com/hwdsl2/docker-embeddings)-Dienst des Stacks (BAAI/bge-small-en-v1.5) und/oder das pgvector-fähige Postgres des Stacks zu nutzen, bearbeite den `anythingllm`-Dienst in `docker-compose.yml`: Kommentiere `EMBEDDING_ENGINE=native` aus und den darunterliegenden Opt-in-Block ein. Kommentiere außerdem den `depends_on`-Hinweis aus, damit die Embeddings-/DB-Dienste zuerst starten. Wenn `VECTOR_DB=pgvector` aktiviert ist und kein `PGVECTOR_CONNECTION_STRING` gesetzt ist, nutzt AnythingLLM automatisch das erzeugte Postgres-Passwort aus `ai-stack-shared`. AnythingLLM erstellt bei der ersten Nutzung automatisch die `vector`-Erweiterung und die Tabelle `anythingllm_vectors`. ⚠️ Das Umstellen des Embedders oder Vektorspeichers bei einer bestehenden Bereitstellung macht zuvor eingebettete Dokumente inkompatibel — bette deine Workspaces nach der Änderung erneut ein.

Detaillierte Konfigurationsoptionen, API-Referenz und Modellverwaltung findest du in der Dokumentation im Repository jedes Dienstes.
