# Installation & getting started

Requirements, installer, GPU setup and uninstalling.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/installation.md)

**Documentation:** **Installation & getting started** · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Quick start (AMD ROCm) — recommended

This variant is rebuilt entirely on **upstream images** and targets **AMD GPUs** (tuned for the **Ryzen AI Max+ 395** / Strix Halo). It uses:

- **[Ollama (ROCm)](https://hub.docker.com/r/ollama/ollama)** as the LLM engine with AMD GPU acceleration
- **[Open WebUI](https://github.com/open-webui/open-webui)** as the chat interface (replaces AnythingLLM)
- **[LiteLLM](https://github.com/BerriAI/litellm)** gateway, **MCP Gateway** + **code sandbox** (tools, incl. `run_python`/`run_shell` for self-testing), **PostgreSQL/pgvector**, **Whisper** (STT) and **Embeddings** (TEI)
- a **[modern status dashboard](architecture.md#dashboard)** showing the live status of every service

Everything is checked and set up by a single script:

```bash
git clone https://github.com/derBerliner1983/self-hosted-llm-stack
cd self-hosted-llm-stack

# Optional: check only, without changing anything
./install.sh --check-only

# Install (checks hardware/ROCm, sets up the firewall, pulls the model, starts everything)
sudo ./install.sh
```

The installer:

- checks **system, RAM and free disk space**
- checks the **AMD GPU/ROCm** (`amdgpu` module, `/dev/kfd`, `/dev/dri`, `video`/`render` groups) and adds your user to the GPU groups
- installs **Docker** and **Docker Compose** if missing
- sets up the **firewall (ufw)** — **LAN-only** by default (SSH open, web UIs reachable only from your local subnet)
- writes a `.env` with auto-generated **secrets** (Postgres password, LiteLLM master key)
- starts the stack, **pulls the default model** and **registers all models with LiteLLM**

**Default model:** `gemma4:12b` (change it with a single line in `.env`, e.g. `DEFAULT_MODEL=qwen2.5:14b`), or pick one at invocation time:

```bash
DEFAULT_MODEL=llama3.1:8b sudo ./install.sh
```

> **Automatic fallback:** If `gemma4:12b` isn't (yet) in Ollama's library, the installer automatically pulls the **fallback model** `gemma3:12b` (configurable via `FALLBACK_MODEL` in `.env`) so it never starts without a model. Once `gemma4:12b` is available, pull it with `docker exec ollama ollama pull gemma4:12b`.

After install:

| Service | URL |
|---|---|
| **Dashboard** (status overview) | `http://<server-ip>:8600` |
| **Chat** (Open WebUI) | `http://<server-ip>:3001` (admin = first account you register) |
| **LiteLLM admin UI** | `http://<server-ip>:4000/ui` (login `admin` + master key, see below) |

## GPU acceleration (AMD ROCm)

For AMD GPUs (e.g. the **Ryzen AI Max+ 395** / Strix Halo), use the ROCm compose file — most easily via the **installer**, or manually:

```bash
docker compose -f docker-compose.rocm.yml up -d --build
```

The `ollama` service uses the official `ollama/ollama:rocm` image and gets the GPU passed through via `/dev/kfd` and `/dev/dri`. `--build` makes sure the locally-built `sandbox-mcp` service (code sandbox) is actually built instead of mistakenly pulled from a registry.

**Requirements:**

- AMD GPU with the `amdgpu` kernel module loaded and **ROCm** (or `amdgpu-dkms`) installed
- The devices `/dev/kfd` and `/dev/dri/renderD*` must be present
- Your user must be in the `video` and `render` groups (the install script handles this)

For the **Ryzen AI Max+ 395** (iGPU `gfx1151`) the stack sets `HSA_OVERRIDE_GFX_VERSION=11.5.1` in case ROCm doesn't detect the iGPU directly. You can adjust this value in `.env`. Thanks to the large unified memory, the iGPU can load very large models.

> **Tip:** The **installer** (`./install.sh`) checks all of this automatically and reports what's missing. If the kernel driver is missing, it **offers to install `amdgpu-dkms`** (just the kernel driver — the ROCm libraries ship inside the container image). Force it with `sudo ./install.sh --install-drivers`, skip it with `--skip-drivers`. For a check without changes: `./install.sh --check-only`.

> **Note:** After a fresh driver install a **reboot** may be required for `/dev/kfd` to appear. Then just run the installer again. If the suggested ROCm version doesn't match your distribution, override it with `ROCM_VERSION=6.x.y sudo ./install.sh --install-drivers`.

## Uninstall

The install script can also clean up — both the new ROCm stack and the **old** stack (AnythingLLM/`hwdsl2` images):

```bash
sudo ./install.sh --uninstall   # remove containers & networks, keep data (volumes)
sudo ./install.sh --purge       # remove EVERYTHING: models, chats, database and .env too
```

`--purge` is irreversible and asks for confirmation first (type `loeschen`; add `-y` to skip the prompt). Firewall rules are left untouched.

> The sections below describe the **original CPU/NVIDIA stack** (the `hwdsl2/*` images and AnythingLLM). For AMD, use the ROCm quick start above.
