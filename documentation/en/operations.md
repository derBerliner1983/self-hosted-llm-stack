# Operations & maintenance

Everyday commands, updating, backups and credentials.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/betrieb.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · [Exchange Bridge](exchange-bridge.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · **Operations & maintenance** · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Useful commands

```bash
./scripts/show-credentials.sh                                 # URLs, master key, passwords
./scripts/wire-mcp.sh                                         # (re-)wire MCP Gateway with LiteLLM + Open WebUI (mcpo)
./scripts/restart-mcp.sh                                      # restart the MCP services — mcpo last, automatically (fixes "MCP session is not available")
./scripts/restart-mcp.sh --build                              # ...also rebuild vault-bridge and sandbox-mcp (after code changes)
./scripts/diagnose-chat.sh <model> ["message"]                # narrow down broken replies layer by layer (Ollama/LiteLLM/WebUI)
LITELLM_KEY_OVERRIDE=<key> ./scripts/diagnose-chat.sh <model>  # ...test with a LiteLLM virtual key instead of the master key
docker compose -f docker-compose.rocm.yml ps                  # status
docker compose -f docker-compose.rocm.yml logs -f open-webui  # logs for one service
docker compose -f docker-compose.rocm.yml down                # stop (data stays in volumes)
```

## Update images

To update all services to the latest versions:

```bash
git pull
docker compose pull
docker compose up -d
./stack-check.sh
```

After the stack restarts, run `./stack-check.sh` to confirm the services and generated credential wiring are healthy.

`git pull` updates all project files (including any changes to compose files); `docker compose pull` updates the service images. If you've customized `docker-compose.yml`, `git pull` will merge changes automatically, or prompt you to resolve conflicts on the same lines.

**One-time note for older installs:** If you set an AnythingLLM password before the `.env` persistence fix, the first container recreation after upgrading may clear that password and leave AnythingLLM unprotected. After updating, open AnythingLLM immediately and confirm password protection is still enabled. If it is not, set a new password in **Settings → Security**. Future container recreations will preserve it.

AnythingLLM is pinned to a stable release tag instead of `latest` because the upstream `latest` image tracks the master branch. When a newer AnythingLLM release is available, back up first, update the tag in the compose files, then run the commands above.

Your data is preserved in the Docker volumes. **Always [back up](#backup-and-restore) before upgrading.**

## Backup and restore

Your API keys, models, and configuration are stored in Docker volumes. Back up before upgrading or making changes:

```bash
# Export API keys (while containers are running)
docker exec ollama ollama_manage --getkey
docker exec litellm litellm_manage --getkey
docker exec mcp mcp_manage --getkey
# Optional services; ignored if the container is not enabled/running
docker exec whisper whisper_manage --getkey 2>/dev/null || true
docker exec whisper-live whisper_live_manage --getkey 2>/dev/null || true
docker exec kokoro kokoro_manage --getkey 2>/dev/null || true
docker exec embeddings embed_manage --getkey 2>/dev/null || true
docker exec docling docling_manage --getkey 2>/dev/null || true

# Back up all volumes (stop services first)
# Stop and remove all containers (data is preserved in Docker volumes)
docker compose down
mkdir -p backups
for vol in ollama-data litellm-data litellm-db ai-stack-shared embeddings-data whisper-data whisper-live-data kokoro-data mcp-data docling-data anythingllm-data caddy-data caddy-config; do
  docker volume inspect "$vol" >/dev/null 2>&1 && \
    docker run --rm -v "${vol}:/source:ro" -v "$(pwd)/backups:/backup" \
      alpine tar czf "/backup/${vol}.tar.gz" -C /source .
done
```

**Note:** Back up `ai-stack-shared` with `litellm-db`; fresh installs store the generated PostgreSQL password there. The `ollama-shared`, `mcp-shared`, and `litellm-shared` volumes are ephemeral key-sharing volumes and do not need to be backed up.

For restore instructions, server migration, and the full pre-upgrade checklist, see the [Backup and Restore](../../docs/backup-restore.md) guide.

## PostgreSQL credentials

Fresh Docker Compose installs generate a random PostgreSQL password automatically and store it in the `ai-stack-shared` volume. Existing default installs continue to use the legacy `litellm` database password for compatibility.

If you previously customized the database password, set `LITELLM_POSTGRES_PASSWORD` in your shell environment to that current password before running `docker compose up -d`, or keep an explicit `LITELLM_DATABASE_URL` override in `litellm.env`.

## Usage counts

Self-Hosted AI Stack uses anonymous, aggregate GitHub release asset download counts to help understand usage and prioritize future improvements. It does not send a telemetry payload or use a private collector.

To disable usage counts when starting the stack:

```bash
AI_STACK_DISABLE_USAGE_COUNTS=1 docker compose up -d
```

## Customization

Each service can be configured with an optional env file. Copy the example env file from the respective repository, edit it, and uncomment the volume mount in `docker-compose.yml`:

| Service | Env file | Repository |
|---|---|---|
| Ollama | `ollama.env` | [docker-ollama](https://github.com/hwdsl2/docker-ollama) |
| LiteLLM | `litellm.env` | [docker-litellm](https://github.com/hwdsl2/docker-litellm) |
| Embeddings | `embed.env` | [docker-embeddings](https://github.com/hwdsl2/docker-embeddings) |
| Whisper | `whisper.env` | [docker-whisper](https://github.com/hwdsl2/docker-whisper) |
| WhisperLive | `whisper-live.env` | [docker-whisper-live](https://github.com/hwdsl2/docker-whisper-live) |
| Kokoro | `kokoro.env` | [docker-kokoro](https://github.com/hwdsl2/docker-kokoro) |
| MCP Gateway | `mcp.env` | [docker-mcp-gateway](https://github.com/hwdsl2/docker-mcp-gateway) |
| Docling | `docling.env` | [docker-docling](https://github.com/hwdsl2/docker-docling) |

AnythingLLM is configured through its web UI at `http://<server-ip>:3001`. You can change the LLM provider, model, embedding engine, and other settings in **Settings**. See [AnythingLLM docs](https://docs.useanything.com/) for more details.

**Use the stack's Embeddings service (optional).** By default AnythingLLM embeds documents in-process with its bundled MiniLM model and stores the vectors in its own LanceDB. To use the stack's [Embeddings](https://github.com/hwdsl2/docker-embeddings) service (BAAI/bge-small-en-v1.5) and/or the stack's pgvector-enabled Postgres instead, edit the `anythingllm` service in `docker-compose.yml`: comment out `EMBEDDING_ENGINE=native` and uncomment the opt-in block beneath it. Also uncomment the `depends_on` note so the embeddings/db services start first. When `VECTOR_DB=pgvector` is enabled and no `PGVECTOR_CONNECTION_STRING` is set, AnythingLLM uses the generated Postgres password from `ai-stack-shared` automatically. AnythingLLM auto-creates the `vector` extension and `anythingllm_vectors` table on first use. ⚠️ Switching the embedder or vector store on an existing deployment makes previously embedded documents incompatible — re-embed your workspaces after the change.

For detailed configuration options, API reference, and model management, see the documentation in each service's repository.
