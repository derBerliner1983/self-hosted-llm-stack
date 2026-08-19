# Weitere Stacks & Alternativen

Der ursprüngliche CPU-/NVIDIA-Stack, leichtgewichtige Varianten, Podman und Beispiel-Pipelines.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/other-stacks.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · **Weitere Stacks**

---

## Schnellstart

**Voraussetzungen:**

- Ein Linux-Server (lokal oder in der Cloud) mit installiertem Docker
- Mindestens 8 GB RAM (mit kleinen Modellen). Für größere LLM-Modelle (8B+) werden 16 GB oder mehr empfohlen.
- Du kannst nicht benötigte Dienste auskommentieren, um den Speicherverbrauch zu reduzieren.

**Den vollständigen Stack starten:**

```bash
# Klone das Repository, um die Compose-Dateien zu erhalten
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack
docker compose up -d
```

> **Bestehende Installationen:** Wenn du dieses Projekt geklont hast, bevor es von `docker-ai-stack` umbenannt wurde, funktionieren dein vorhandener Checkout und deine Bereitstellung weiterhin. GitHub leitet die alte Repository-URL um, und du musst dein lokales Verzeichnis, deine Container, Volumes oder Netzwerke nicht umbenennen.

> **PostgreSQL-Zugangsdaten:** Neue Installationen und bestehende Standardinstallationen werden automatisch behandelt. Wenn du zuvor ein eigenes Datenbankpasswort festgelegt hast, siehe [PostgreSQL-Zugangsdaten](betrieb.md#postgresql-zugangsdaten), bevor du startest.

**Ein Modell herunterladen** (erforderlich, bevor LLM-Anfragen gestellt werden):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

Führe den Health-Check aus, um zu überprüfen, ob alle Dienste funktionieren:

```bash
./stack-check.sh
```

> **Tipp:** Beim ersten Start kann die Initialisierung der Dienste einige Minuten dauern. Wenn Prüfungen fehlschlagen, warte und führe `./stack-check.sh` erneut aus. Nutze `docker compose logs`, um den Fortschritt zu prüfen.

Für detaillierte Fehlerbehebung siehe die Anleitung zur [Fehlerbehebung](../../docs/troubleshooting.md).

**Den LiteLLM-Masterschlüssel abrufen** (wird zum Anmelden in der Admin-UI und für LLM-Anfragen verwendet):

```bash
docker exec litellm litellm_manage --showkey
```

<details>
<summary>Kern-API-Schlüssel anzeigen (Ollama, LiteLLM, MCP Gateway)</summary>

```bash
docker exec ollama ollama_manage --showkey
docker exec litellm litellm_manage --showkey
docker exec mcp mcp_manage --showkey
```

</details>

**Auf AnythingLLM (Chat-UI) zugreifen:**

AnythingLLM ist vorkonfiguriert, um sich über LiteLLM mit deinem lokalen LLM zu verbinden. Beim ersten Start kann es einige Minuten dauern, bis es verfügbar ist (prüfe den Fortschritt mit `docker logs anythingllm`).

**Standardmäßig passwortgeschützt.** Beim ersten Start wird ein zufälliges Admin-Passwort automatisch erzeugt, einmalig in `docker logs anythingllm` ausgegeben und in `/app/server/storage/.initial_admin_password` innerhalb des `anythingllm-data`-Volumes gespeichert. Das voreingestellte Passwort bleibt über Container-Upgrades hinweg erhalten. Ändere es jederzeit unter **Settings → Security**; danach stimmt `.initial_admin_password` möglicherweise nicht mehr mit dem aktuellen Anmeldepasswort überein.

Das automatisch erzeugte Passwort abrufen:

```bash
# Jederzeit aus dem Daten-Volume:
docker exec anythingllm cat /app/server/storage/.initial_admin_password

# Oder aus den Live-Logs (nur beim ersten Start angezeigt):
docker compose logs anythingllm | grep -A4 "FIRST RUN"
```

Öffne `http://<server-ip>:3001` in deinem Browser und melde dich mit dem obigen Passwort an.

> **Tipp:** Wenn du AnythingLLM über `localhost` oder ein vertrauenswürdiges LAN hinaus verfügbar machst, nutze das mitgelieferte Caddy-HTTPS-Overlay, damit das Passwort während der Übertragung verschlüsselt wird und direkte HTTP-Ports an localhost gebunden sind. Siehe [Ins Internet gerichtete Bereitstellungen](sicherheit.md#ins-internet-gerichtete-bereitstellungen) weiter unten.

**Auf die LiteLLM-Admin-UI zugreifen:**

Öffne `http://<server-ip>:4000/ui` in deinem Browser. Melde dich mit dem Benutzernamen `admin` und deinem LiteLLM-Masterschlüssel als Passwort an. Die UI bietet Verwaltung virtueller Schlüssel, Ausgabenverfolgung und Modellkonfiguration.

> **Tipp:** Klicke in der Admin-UI im linken Menü auf **Playground**. Wähle ein lokales Modell (z. B. `ollama-chat/llama3.2:3b`) aus dem Dropdown-Menü und beginne zu chatten — eine schnelle Möglichkeit, um zu überprüfen, ob dein lokales LLM durchgängig funktioniert.

**Den Stack stoppen:**

```bash
# Alle Container stoppen und entfernen (Daten bleiben in Docker-Volumes erhalten)
docker compose down
```

## Leichtgewichtige Stacks

Du brauchst nicht den vollständigen Stack? Nutze eine vorkonfigurierte Teilmenge aus dem `stacks/`-Ordner:

> **Hinweis:** Die leichtgewichtigen Stacks teilen sich standardmäßig Container-Namen, Ports und Docker-Volume-Namen. Führe mit den Standard-Compose-Dateien immer nur eine Stack-Variante gleichzeitig aus; stoppe die aktuelle Variante, bevor du zu einer anderen wechselst. Um Funktionen zu kombinieren, nutze den vollständigen Stack oder passe Compose-Projektnamen, Container-Namen, Ports und Volumes an.

| Stack | Dienste | Speicher | Anwendungsfall |
|---|---|---|---|
| **[chat-ui](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/chat-ui)** | Ollama + LiteLLM + AnythingLLM | ~5 GB | Web-basierte ChatGPT-ähnliche Chat-Oberfläche |
| **[voice-pipeline](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/voice-pipeline)** | Whisper + Ollama + LiteLLM + Kokoro | ~6 GB | Sprache-zu-Text → LLM → Text-zu-Sprache |
| **[voice-chat](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/voice-chat)** | Whisper + Ollama + LiteLLM + Kokoro + AnythingLLM | ~6,5 GB | Chat-UI mit Sprachein-/-ausgabe |
| **[rag-pipeline](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/rag-pipeline)** | Ollama + LiteLLM + Embeddings | ~5 GB | Semantische Suche + LLM-Frage & Antwort |
| **[rag-pipeline-full](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/rag-pipeline-full)** | Ollama + LiteLLM + Embeddings + Docling | ~6 GB | Dokumentenanalyse + semantische Suche + LLM-Frage & Antwort |
| **[code-assistant](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/code-assistant)** | Ollama + LiteLLM + MCP Gateway + Embeddings | ~5 GB | KI-Programmierung mit Werkzeugen + semantische Codesuche |
| **[ai-tools](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/ai-tools)** | Ollama + LiteLLM + MCP Gateway | ~5 GB | KI-Programmierassistent mit Werkzeugzugriff |
| **[chat-only](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/chat-only)** | Ollama + LiteLLM | ~4,5 GB | Minimaler lokaler ChatGPT-Ersatz |

```bash
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack/stacks/chat-ui  # oder voice-pipeline, voice-chat, rag-pipeline, rag-pipeline-full, code-assistant, ai-tools, chat-only
docker compose up -d
```

## Architektur (CPU-/NVIDIA-Stack)

```mermaid
graph LR
    A["🎤 Audio-Eingabe"] -->|transkribieren| W["Whisper<br/>(Sprache-zu-Text)"]
    D["📄 Dokumente"] -->|parsen| DC["Docling<br/>(Dokument → Text)"]
    DC -->|einbetten| E["Embeddings<br/>(Text → Vektoren)"]
    E -->|speichern| VDB["pgvector<br/>(im gemeinsamen Postgres)"]
    W -->|Abfrage| E
    VDB -->|Kontext| L["LiteLLM<br/>(KI-Gateway)"]
    W -->|Text| L
    L -->|leitet weiter an| O["Ollama<br/>(lokales LLM)"]
    L -->|Antwort| T["Kokoro TTS<br/>(Text-zu-Sprache)"]
    T --> B["🔊 Audio-Ausgabe"]
    C["🤖 KI-Client<br/>(Cline, Claude usw.)"] -->|MCP-Werkzeuge| M["MCP Gateway<br/>(MCP-Endpunkt)"]
    C -->|Chat| L
    L -->|MCP-Protokoll| M
    U["👤 Benutzer"] -->|Chat| AN["AnythingLLM<br/>(Chat-UI)"]
    AN -->|LLM-Anfragen| L
    AN -->|MCP-Werkzeuge| M
    U -->|nutzen| C
    U -->|sprechen| A
    U -->|hochladen| D
```

**Hinweise:**

- Der Port von Ollama (`11434`) und der Port des MCP Gateway (`3000`) sind interne Ports des Docker-Netzwerks und werden standardmäßig nicht an den Host weitergegeben. Greife über LiteLLM auf Port `4000` auf dein LLM zu.
- Kokoro (TTS), Docling (Dokumentenanalyse) und WhisperLive (Echtzeit-STT) sind standardmäßig deaktiviert, um den Speicherverbrauch zu reduzieren. Kommentiere diese Dienste in `docker-compose.yml` aus, um sie zu aktivieren.

## Ausführung ohne Docker Compose

Wenn du lieber direkt `docker run`-Befehle verwendest, erstelle zunächst ein gemeinsames Netzwerk, damit die Dienste miteinander kommunizieren können:

```bash
docker network create ai-stack
```

Erzeuge dann ein PostgreSQL-Passwort und starte jeden Dienst im gemeinsamen Netzwerk:

> **Hinweis:** Warte bei manuellem `docker run`, bis jede Abhängigkeit bereit ist, bevor du Dienste startest, die sie nutzen (warte zum Beispiel auf PostgreSQL und weitere Abhängigkeiten wie Ollama oder MCP, bevor du LiteLLM startest; wenn du AnythingLLM nutzt, warte auf LiteLLM, bevor du es startest). Die folgenden Beispiele erzeugen eine PostgreSQL-Passwortvariable und verwenden sie für Postgres und LiteLLM wieder.

```bash
LITELLM_POSTGRES_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

# PostgreSQL mit pgvector (von LiteLLM benötigt; pgvector ermöglicht Vektorspeicherung für RAG)
docker run -d --name litellm-db --restart always \
    --network ai-stack \
    -e POSTGRES_USER=litellm \
    -e POSTGRES_PASSWORD="$LITELLM_POSTGRES_PASSWORD" \
    -e POSTGRES_DB=litellm \
    -v litellm-db:/var/lib/postgresql \
    pgvector/pgvector:pg18-trixie

# Ollama (LLM)
docker run -d --name ollama --restart always \
    --network ai-stack \
    -v ollama-data:/var/lib/ollama \
    -v ollama-shared:/var/lib/ollama-shared \
    hwdsl2/ollama-server

# MCP Gateway
docker run -d --name mcp --restart always \
    --network ai-stack \
    -v mcp-data:/var/lib/mcp \
    -v mcp-shared:/var/lib/mcp-shared \
    hwdsl2/mcp-gateway

# LiteLLM (KI-Gateway)
docker run -d --name litellm --restart always \
    --network ai-stack \
    -p 4000:4000 \
    -e LITELLM_OLLAMA_BASE_URL=http://ollama:11434 \
    -e LITELLM_MCP_URL=http://mcp:3000/mcp \
    -e LITELLM_DATABASE_URL="postgresql://litellm:${LITELLM_POSTGRES_PASSWORD}@litellm-db:5432/litellm" \
    -v litellm-data:/etc/litellm \
    -v ollama-shared:/var/lib/ollama-shared:ro \
    -v mcp-shared:/var/lib/mcp-shared:ro \
    -v litellm-shared:/var/lib/litellm-shared \
    hwdsl2/litellm-server

# Embeddings
docker run -d --name embeddings --restart always \
    --network ai-stack \
    -p 127.0.0.1:8000:8000 \
    -v embeddings-data:/var/lib/embeddings \
    hwdsl2/embeddings-server

# Whisper (STT)
docker run -d --name whisper --restart always \
    --network ai-stack \
    -p 127.0.0.1:9000:9000 \
    -v whisper-data:/var/lib/whisper \
    hwdsl2/whisper-server

# WhisperLive (Echtzeit-STT)
docker run -d --name whisper-live --restart always \
    --network ai-stack \
    -p 127.0.0.1:9090:9090 \
    -v whisper-live-data:/var/lib/whisper-live \
    hwdsl2/whisper-live-server

# AnythingLLM (Chat-UI)
docker run -d --name anythingllm --restart always \
    --network ai-stack \
    -p 3001:3001 \
    -e STORAGE_DIR=/app/server/storage \
    -e LLM_PROVIDER=generic-openai \
    -e GENERIC_OPEN_AI_BASE_PATH=http://litellm:4000/v1 \
    -e GENERIC_OPEN_AI_MODEL_PREF=ollama/llama3.2:3b \
    -e GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=131072 \
    -e ANYTHINGLLM_DEFAULT_CHAT_MODE=chat \
    -e EMBEDDING_ENGINE=native \
    -e DISABLE_TELEMETRY=true \
    -v anythingllm-data:/app/server/storage \
    -v litellm-shared:/var/lib/litellm-shared:ro \
    -v "$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro" \
    --entrypoint /bin/bash \
    mintplexlabs/anythingllm:1.15.0 \
    /usr/local/bin/chat-ui-bootstrap.sh

# Kokoro (TTS)
docker run -d --name kokoro --restart always \
    --network ai-stack \
    -p 127.0.0.1:8880:8880 \
    -v kokoro-data:/var/lib/kokoro \
    hwdsl2/kokoro-server

# Docling (Dokumentenanalyse)
docker run -d --name docling --restart always \
    --network ai-stack \
    -p 127.0.0.1:5001:5001 \
    -v docling-data:/var/lib/docling \
    hwdsl2/docling-server
```

**Hinweis:** Das gemeinsame Netzwerk erlaubt es den Diensten, sich gegenseitig über den Container-Namen zu erreichen (z. B. verbindet sich LiteLLM über `http://ollama:11434` mit Ollama). Du kannst nur die Dienste starten, die du benötigst — sie müssen nicht alle zusammen laufen.

**Ein Modell herunterladen** (erforderlich, bevor LLM-Anfragen gestellt werden):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

## Podman verwenden

Der Stack läuft nach bestem Bemühen unter [Podman](https://podman.io/). Die CPU-Compose-Dateien funktionieren unverändert; GPU-Beschleunigung und Hosts mit aktiviertem SELinux benötigen einige zusätzliche Schritte, die unten beschrieben werden. Podman **4.1+** wird empfohlen.

**1. Installiere den Docker-CLI-Shim.** Damit die `docker`-Befehle in dieser README und der `stack-check.sh`-Health-Check unverändert funktionieren, installiere das Paket `podman-docker` (stellt einen `docker` → `podman`-Wrapper bereit):

```bash
# Fedora / RHEL / CentOS Stream
sudo dnf install -y podman-docker

# Debian / Ubuntu
sudo apt-get install -y podman-docker
```

> **Hinweis:** Ein Shell-`alias docker=podman` ist **nicht** ausreichend — Aliase werden von Skripten wie `stack-check.sh` nicht erkannt. Nutze stattdessen das Paket `podman-docker` (oder einen `docker` → `podman`-Symlink in deinem `PATH`). Alternativ erkennt `stack-check.sh` Podman automatisch; du kannst es auch mit `CONTAINER_ENGINE=podman ./stack-check.sh` erzwingen.

**2. Installiere einen Compose-Provider.** `podman compose` delegiert an einen externen Provider. Installiere entweder `podman-compose` oder `docker-compose`:

```bash
# Fedora / RHEL / CentOS Stream
sudo dnf install -y podman-compose

# Debian / Ubuntu
sudo apt-get install -y podman-compose
```

**3. Starte den Stack.** Mit installiertem Shim funktioniert jeder Befehl in dieser README unverändert. Ohne ihn ersetze `docker` durch `podman`:

```bash
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack
podman compose up -d
```

Führe den Health-Check aus (erkennt die Engine automatisch):

```bash
./stack-check.sh
```

**GPU-Beschleunigung (CDI).** Podman liest den Compose-`deploy.resources`-GPU-Block nicht. Nutze stattdessen das [Container Device Interface (CDI)](https://github.com/cncf-tags/container-device-interface). Erzeuge nach der Installation des [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) eine CDI-Spezifikation:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Stelle dann die GPU den relevanten Diensten zur Verfügung. Ersetze für `podman compose` den `deploy:`-Block in `docker-compose.cuda.yml` durch einen `devices:`-Eintrag für die Dienste `ollama` (und `whisper`):

```yaml
    devices:
      - nvidia.com/gpu=all
```

Für einen einfachen `podman run`-Befehl füge `--device nvidia.com/gpu=all` hinzu.

**SELinux.** Auf Hosts mit aktiviertem SELinux (Fedora, RHEL, CentOS Stream) benötigen per Bind eingebundene Dateien einen Relabel-Suffix, sonst wird dem Container der Zugriff verweigert. Füge `:z` (gemeinsam) zum `chat-ui-bootstrap.sh`-Bind-Mount hinzu:

- In `docker-compose.yml`: Ändere `./chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro` zu `./chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro,z`
- Im obigen `podman run`-Befehl: Ändere `"$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro"` zu `"$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro,z"`

Benannte Volumes benötigen kein Relabeling.

**Nächste Schritte:** Lade ein Modell herunter und greife auf die Dienste zu — folge den Anweisungen im [Schnellstart](#schnellstart) ab „Ein Modell herunterladen". Mit installiertem `podman-docker`-Shim funktionieren alle Befehle unverändert.

## Beispiel für eine Sprach-Pipeline

Transkribiere eine gesprochene Frage, erhalte über Ollama eine lokale LLM-Antwort und wandle sie in Sprache um:

**Hinweis:** Kokoro (TTS) ist standardmäßig deaktiviert. Um dieses Beispiel zu nutzen, kommentiere zunächst den `kokoro`-Dienst in `docker-compose.yml` aus und führe dann `docker compose up -d` aus.

**Tipp:** Brauchst du eine Beispiel-Audiodatei? Lade dieses englische Sprachbeispiel (WAV, MIT-Lizenz) aus dem [Azure Samples](https://github.com/Azure-Samples/cognitive-services-speech-sdk)-Repository herunter:

```bash
curl -L -o sample_speech.wav \
    "https://github.com/Azure-Samples/cognitive-services-speech-sdk/raw/master/sampledata/audiofiles/katiesteve.wav"
```

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)
WHISPER_KEY=$(docker exec whisper whisper_manage --getkey)
KOKORO_KEY=$(docker exec kokoro kokoro_manage --getkey)

# Schritt 1: Audio in Text transkribieren (Whisper)
TEXT=$(curl -s http://localhost:9000/v1/audio/transcriptions \
    -H "Authorization: Bearer $WHISPER_KEY" \
    -F file=@sample_speech.wav -F model=whisper-1 | jq -r .text)

# Schritt 2: Text über LiteLLM an Ollama senden und eine Antwort erhalten
RESPONSE=$(curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"ollama/llama3.2:3b\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEXT\"}]}" \
    | jq -r '.choices[0].message.content')

# Schritt 3: Die Antwort in Sprache umwandeln (Kokoro TTS)
curl -s http://localhost:8880/v1/audio/speech \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $KOKORO_KEY" \
    -d "{\"model\":\"tts-1\",\"input\":\"$RESPONSE\",\"voice\":\"af_heart\"}" \
    --output response.mp3
```

## Vektordatenbank

Das PostgreSQL des Stacks wird mit der [pgvector](https://github.com/pgvector/pgvector)-Erweiterung ausgeliefert, sodass du Embeddings in derselben Datenbank speichern und abfragen kannst, die auch LiteLLM verwendet — es ist keine separate Vektordatenbank erforderlich.

Aktiviere die Erweiterung einmalig (die Datenbank bleibt bestehen, dies muss also nur ein einziges Mal getan werden):

```bash
docker exec litellm-db psql -U litellm -d litellm -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```

Überprüfe, ob sie aktiviert ist:

```bash
docker exec litellm-db psql -U litellm -d litellm -c "SELECT extname, extversion FROM pg_extension WHERE extname='vector';"
```

Du kannst dann eine Tabelle mit einer `vector`-Spalte erstellen (nutze die Dimension deines Embedding-Modells — z. B. `384` für das Standardmodell `BAAI/bge-small-en-v1.5`) und mit dem `<=>`-Operator eine Ähnlichkeitssuche durchführen. Für größere oder hybride Suchen kannst du stattdessen eine dedizierte Vektordatenbank wie Qdrant oder Chroma betreiben.

## Beispiel für eine RAG-Pipeline

Bette Dokumente für die semantische Suche ein, rufe Kontext ab und beantworte dann Fragen mit einem lokalen Ollama-Modell:

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)
EMBED_KEY=$(docker exec embeddings embed_manage --getkey)

# Schritt 1: Einen Dokumentabschnitt einbetten und den Vektor in deiner Vektor-DB speichern
curl -s http://localhost:8000/v1/embeddings \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $EMBED_KEY" \
    -d '{"input": "Docker simplifies deployment by packaging apps in containers.", "model": "text-embedding-ada-002"}' \
    | jq '.data[0].embedding'
# → Speichere den zurückgegebenen Vektor zusammen mit dem Quelltext in pgvector (im Postgres des Stacks enthalten) oder einer anderen Vektor-DB wie Qdrant oder Chroma.

# Schritt 2: Bette zur Abfragezeit die Frage ein, rufe die am besten passenden Abschnitte aus
#          der Vektor-DB ab und sende dann die Frage und den abgerufenen Kontext über LiteLLM an Ollama.
curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "ollama/llama3.2:3b",
      "messages": [
        {"role": "system", "content": "Answer using only the provided context."},
        {"role": "user", "content": "What does Docker do?\n\nContext: Docker simplifies deployment by packaging apps in containers."}
      ]
    }' \
    | jq -r '.choices[0].message.content'
```
