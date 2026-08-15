# Managing models

Pulling, unloading and registering models with LiteLLM.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/modelle.md)

**Documentation:** [Installation & getting started](installation.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [Code sandbox](code-sandbox.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · **Managing models** · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Register models with LiteLLM

New models get registered with LiteLLM **automatically** — whether you pull them via the [dashboard's model manager](architecture.md#dashboard) or directly with `docker exec ollama ollama pull …`. The dashboard reconciles in the background roughly every 60 seconds, registering any installed Ollama model LiteLLM doesn't know yet under `ollama/<model>` (idempotent — already-registered ones are skipped), and triggers an immediate sync right after a dashboard-initiated download instead of waiting for the next interval. Status ("✓ auto-synced with LiteLLM …") is shown in the dashboard's "Load models" popup.

This needs `LITELLM_MASTER_KEY` to reach the dashboard container (`install.sh`/`.env` do this automatically); without a key the popup shows "⚠ automatic LiteLLM registration inactive" and you register manually instead:

```bash
docker exec ollama ollama pull qwen2.5:14b
./scripts/sync-ollama-models.sh
```

The script stays available as a manual fallback (e.g. for instant control instead of waiting up to 60s) and is likewise **idempotent**.
