# Other stacks & alternatives

The original CPU/NVIDIA stack, lightweight variants, Podman and example pipelines.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/weitere-stacks.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · **Other stacks**

---

## Quick start

**Requirements:**

- A Linux server (local or cloud) with Docker installed
- At least 8 GB of RAM (with small models). For larger LLM models (8B+), 16 GB or more is recommended.
- You can comment out services you don't need to reduce memory usage.

**Start the full stack:**

```bash
# Clone the repository to get the compose files
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack
docker compose up -d
```

> **Existing installs:** If you cloned this project before it was renamed from `docker-ai-stack`, your existing checkout and deployment continue to work. GitHub redirects the old repository URL, and you do not need to rename your local directory, containers, volumes, or networks.

> **PostgreSQL credentials:** Fresh installs and existing default installs are handled automatically. If you previously set a custom database password, see [PostgreSQL credentials](operations.md#postgresql-credentials) before starting.

**Pull a model** (required before making LLM requests):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

Run the health check to verify all services are working:

```bash
./stack-check.sh
```

> **Tip:** On first start, services may take a few minutes to initialize. If any checks fail, wait and run `./stack-check.sh` again. Use `docker compose logs` to check progress.

For detailed troubleshooting, see the [Troubleshooting](../../docs/troubleshooting.md) guide.

**Get the LiteLLM master key** (used to log into the Admin UI and for LLM requests):

```bash
docker exec litellm litellm_manage --showkey
```

<details>
<summary>Show core API keys (Ollama, LiteLLM, MCP Gateway)</summary>

```bash
docker exec ollama ollama_manage --showkey
docker exec litellm litellm_manage --showkey
docker exec mcp mcp_manage --showkey
```

</details>

**Access AnythingLLM (Chat UI):**

AnythingLLM is pre-configured to connect to your local LLM via LiteLLM. On first start, it may take a few minutes to become available (check progress with `docker logs anythingllm`).

**Password-protected by default.** A random admin password is auto-generated on first start, printed once to `docker logs anythingllm`, and saved to `/app/server/storage/.initial_admin_password` inside the `anythingllm-data` volume. The seeded password persists across container upgrades. Change it any time from **Settings → Security**; after you do, `.initial_admin_password` may no longer match the current login password.

Retrieve the auto-generated password:

```bash
# At any time from the data volume:
docker exec anythingllm cat /app/server/storage/.initial_admin_password

# Or from the live logs (only shown on first start):
docker compose logs anythingllm | grep -A4 "FIRST RUN"
```

Open `http://<server-ip>:3001` in your browser and log in with the password above.

> **Tip:** When exposing AnythingLLM beyond `localhost` or a trusted LAN, use the included Caddy HTTPS overlay so the password is encrypted in transit and direct HTTP ports are bound to localhost. See [Internet-facing deployments](security.md#internet-facing-deployments) below.

**Access the LiteLLM Admin UI:**

Open `http://<server-ip>:4000/ui` in your browser. Log in with username `admin` and your LiteLLM master key as the password. The UI provides virtual key management, spend tracking, and model configuration.

> **Tip:** In the Admin UI, click **Playground** in the left menu. Select a local model (e.g., `ollama-chat/llama3.2:3b`) from the dropdown and start chatting — a quick way to verify your local LLM is working end-to-end.

**Stop the stack:**

```bash
# Stop and remove all containers (data is preserved in Docker volumes)
docker compose down
```

## Lightweight stacks

Don't need the full stack? Use a pre-configured subset from the `stacks/` folder:

> **Note:** The lightweight stacks share default container names, ports, and Docker volume names. Run one stack variant at a time with the default compose files; stop the current variant before switching to another. To combine capabilities, use the full stack or customize Compose project names, container names, ports, and volumes.

| Stack | Services | Memory | Use case |
|---|---|---|---|
| **[chat-ui](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/chat-ui)** | Ollama + LiteLLM + AnythingLLM | ~5 GB | Web-based ChatGPT-like chat interface |
| **[voice-pipeline](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/voice-pipeline)** | Whisper + Ollama + LiteLLM + Kokoro | ~6 GB | Speech-to-text → LLM → text-to-speech |
| **[voice-chat](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/voice-chat)** | Whisper + Ollama + LiteLLM + Kokoro + AnythingLLM | ~6.5 GB | Chat UI with voice input/output |
| **[rag-pipeline](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/rag-pipeline)** | Ollama + LiteLLM + Embeddings | ~5 GB | Semantic search + LLM Q&A |
| **[rag-pipeline-full](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/rag-pipeline-full)** | Ollama + LiteLLM + Embeddings + Docling | ~6 GB | Document parsing + semantic search + LLM Q&A |
| **[code-assistant](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/code-assistant)** | Ollama + LiteLLM + MCP Gateway + Embeddings | ~5 GB | AI coding with tools + semantic code search |
| **[ai-tools](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/ai-tools)** | Ollama + LiteLLM + MCP Gateway | ~5 GB | AI coding assistant with tool access |
| **[chat-only](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/chat-only)** | Ollama + LiteLLM | ~4.5 GB | Minimal local ChatGPT replacement |

```bash
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack/stacks/chat-ui  # or voice-pipeline, voice-chat, rag-pipeline, rag-pipeline-full, code-assistant, ai-tools, chat-only
docker compose up -d
```

## Architecture (CPU/NVIDIA stack)

```mermaid
graph LR
    A["🎤 Audio input"] -->|transcribe| W["Whisper<br/>(speech-to-text)"]
    D["📄 Documents"] -->|parse| DC["Docling<br/>(document → text)"]
    DC -->|embed| E["Embeddings<br/>(text → vectors)"]
    E -->|store| VDB["pgvector<br/>(in shared Postgres)"]
    W -->|query| E
    VDB -->|context| L["LiteLLM<br/>(AI gateway)"]
    W -->|text| L
    L -->|routes to| O["Ollama<br/>(local LLM)"]
    L -->|response| T["Kokoro TTS<br/>(text-to-speech)"]
    T --> B["🔊 Audio output"]
    C["🤖 AI client<br/>(Cline, Claude, etc.)"] -->|MCP tools| M["MCP Gateway<br/>(MCP endpoint)"]
    C -->|chat| L
    L -->|MCP protocol| M
    U["👤 User"] -->|chat| AN["AnythingLLM<br/>(chat UI)"]
    AN -->|LLM requests| L
    AN -->|MCP tools| M
    U -->|use| C
    U -->|speak| A
    U -->|upload| D
```

**Notes:**

- Ollama's port (`11434`) and MCP Gateway's port (`3000`) are internal to the Docker network and not exposed to the host by default. Access your LLM through LiteLLM on port `4000`.
- Kokoro (TTS), Docling (document parsing), and WhisperLive (real-time STT) are disabled by default to reduce memory usage. Uncomment these services in `docker-compose.yml` to enable them.

## Running without Docker Compose

If you prefer using `docker run` commands directly, first create a shared network so services can communicate:

```bash
docker network create ai-stack
```

Then generate a PostgreSQL password and start each service on the shared network:

> **Note:** With manual `docker run`, wait for each dependency to become ready before starting services that use it (for example, wait for PostgreSQL and any other dependencies, such as Ollama or MCP, before LiteLLM; if using AnythingLLM, wait for LiteLLM before starting it). The examples below generate one PostgreSQL password variable and reuse it for Postgres and LiteLLM.

```bash
LITELLM_POSTGRES_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

# PostgreSQL with pgvector (required by LiteLLM; pgvector enables vector storage for RAG)
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

# LiteLLM (AI gateway)
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

# WhisperLive (real-time STT)
docker run -d --name whisper-live --restart always \
    --network ai-stack \
    -p 127.0.0.1:9090:9090 \
    -v whisper-live-data:/var/lib/whisper-live \
    hwdsl2/whisper-live-server

# AnythingLLM (chat UI)
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

# Docling (document parsing)
docker run -d --name docling --restart always \
    --network ai-stack \
    -p 127.0.0.1:5001:5001 \
    -v docling-data:/var/lib/docling \
    hwdsl2/docling-server
```

**Note:** The shared network allows services to reach each other by container name (e.g., LiteLLM connects to Ollama via `http://ollama:11434`). You can start only the services you need — they don't all have to run together.

**Pull a model** (required before making LLM requests):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

## Using Podman

The stack runs under [Podman](https://podman.io/) on a best-effort basis. The CPU compose files work as-is; GPU acceleration and SELinux-enabled hosts need a couple of extra steps described below. Podman **4.1+** is recommended.

**1. Install the Docker CLI shim.** So that the `docker` commands in this README and the `stack-check.sh` health check work unchanged, install the `podman-docker` package (provides a `docker` → `podman` wrapper):

```bash
# Fedora / RHEL / CentOS Stream
sudo dnf install -y podman-docker

# Debian / Ubuntu
sudo apt-get install -y podman-docker
```

> **Note:** A shell `alias docker=podman` is **not** sufficient — aliases are not seen by scripts such as `stack-check.sh`. Use the `podman-docker` package (or a `docker` → `podman` symlink in your `PATH`) instead. Alternatively, `stack-check.sh` auto-detects Podman; you can also force it with `CONTAINER_ENGINE=podman ./stack-check.sh`.

**2. Install a Compose provider.** `podman compose` delegates to an external provider. Install either `podman-compose` or `docker-compose`:

```bash
# Fedora / RHEL / CentOS Stream
sudo dnf install -y podman-compose

# Debian / Ubuntu
sudo apt-get install -y podman-compose
```

**3. Start the stack.** With the shim installed, every command in this README works unchanged. Without it, substitute `podman` for `docker`:

```bash
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack
podman compose up -d
```

Run the health check (auto-detects the engine):

```bash
./stack-check.sh
```

**GPU acceleration (CDI).** Podman does not read the Compose `deploy.resources` GPU block. Instead, use the [Container Device Interface (CDI)](https://github.com/cncf-tags/container-device-interface). After installing the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), generate a CDI spec:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Then expose the GPU to the relevant services. For `podman compose`, replace the `deploy:` block in `docker-compose.cuda.yml` with a `devices:` entry for the `ollama` (and `whisper`) services:

```yaml
    devices:
      - nvidia.com/gpu=all
```

For a plain `podman run` command, add `--device nvidia.com/gpu=all`.

**SELinux.** On SELinux-enabled hosts (Fedora, RHEL, CentOS Stream), bind-mounted files need a relabel suffix, or the container will be denied access. Add `:z` (shared) to the `chat-ui-bootstrap.sh` bind mount:

- In `docker-compose.yml`: change `./chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro` to `./chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro,z`
- In the `podman run` command above: change `"$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro"` to `"$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro,z"`

Named volumes do not need relabeling.

**Next steps:** Pull a model and access the services — follow the instructions in [Quick start](#quick-start) starting from "Pull a model." With the `podman-docker` shim installed, all commands work unchanged.

## Voice pipeline example

Transcribe a spoken question, get a local LLM response via Ollama, and convert it to speech:

**Note:** Kokoro (TTS) is disabled by default. To use this example, first uncomment the `kokoro` service in `docker-compose.yml`, then run `docker compose up -d`.

**Tip:** Need a sample audio file? Download this English speech sample (WAV, MIT License) from the [Azure Samples](https://github.com/Azure-Samples/cognitive-services-speech-sdk) repository:

```bash
curl -L -o sample_speech.wav \
    "https://github.com/Azure-Samples/cognitive-services-speech-sdk/raw/master/sampledata/audiofiles/katiesteve.wav"
```

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)
WHISPER_KEY=$(docker exec whisper whisper_manage --getkey)
KOKORO_KEY=$(docker exec kokoro kokoro_manage --getkey)

# Step 1: Transcribe audio to text (Whisper)
TEXT=$(curl -s http://localhost:9000/v1/audio/transcriptions \
    -H "Authorization: Bearer $WHISPER_KEY" \
    -F file=@sample_speech.wav -F model=whisper-1 | jq -r .text)

# Step 2: Send text to Ollama via LiteLLM and get a response
RESPONSE=$(curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"ollama/llama3.2:3b\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEXT\"}]}" \
    | jq -r '.choices[0].message.content')

# Step 3: Convert the response to speech (Kokoro TTS)
curl -s http://localhost:8880/v1/audio/speech \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $KOKORO_KEY" \
    -d "{\"model\":\"tts-1\",\"input\":\"$RESPONSE\",\"voice\":\"af_heart\"}" \
    --output response.mp3
```

## Vector database

The stack's PostgreSQL ships with the [pgvector](https://github.com/pgvector/pgvector) extension, so you can store and query embeddings in the same database that LiteLLM uses — no separate vector database required.

Enable the extension once (the database persists, so this only needs to be done a single time):

```bash
docker exec litellm-db psql -U litellm -d litellm -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```

Verify it is enabled:

```bash
docker exec litellm-db psql -U litellm -d litellm -c "SELECT extname, extversion FROM pg_extension WHERE extname='vector';"
```

You can then create a table with a `vector` column (use the dimension of your embedding model — e.g. `384` for the default `BAAI/bge-small-en-v1.5`) and run similarity search with the `<=>` operator. For larger-scale or hybrid search, you can run a dedicated vector database such as Qdrant or Chroma instead.

## RAG pipeline example

Embed documents for semantic search, retrieve context, then answer questions with a local Ollama model:

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)
EMBED_KEY=$(docker exec embeddings embed_manage --getkey)

# Step 1: Embed a document chunk and store the vector in your vector DB
curl -s http://localhost:8000/v1/embeddings \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $EMBED_KEY" \
    -d '{"input": "Docker simplifies deployment by packaging apps in containers.", "model": "text-embedding-ada-002"}' \
    | jq '.data[0].embedding'
# → Store the returned vector alongside the source text in pgvector (included in the stack's Postgres), or another vector DB such as Qdrant or Chroma.

# Step 2: At query time, embed the question, retrieve the top matching chunks from
#          the vector DB, then send the question and retrieved context to Ollama via LiteLLM.
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
