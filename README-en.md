[Deutsch](README.md) | [English](README-en.md)

# Self-Hosted AI Stack

[![Powered by Docker Compose](docs/images/powered-by-docker-compose.svg)](https://docs.docker.com/compose/) &nbsp;[![Docker Pulls](https://raw.githubusercontent.com/hwdsl2/badges/main/img/docker-pulls-ai-stack.svg)](https://hub.docker.com/u/hwdsl2) &nbsp;[![License: MIT](docs/images/license.svg)](https://opensource.org/licenses/MIT)

<p align="center">
  <img src="docs/images/self-hosted-ai-stack-overview.png"
       alt="Self-Hosted AI Stack: deploy a complete self-hosted AI stack with one command"
       width="100%">
</p>
<p align="center"><sub>Shows the general concept of the original CPU/NVIDIA variant. For the current AMD ROCm stack diagram, see the <a href="#architecture">Architecture section</a> below.</sub></p>

Includes Ollama, LiteLLM, AnythingLLM, Whisper, MCP Gateway, Embeddings, Docling, and Kokoro — fully configured and ready to run with Docker Compose.

- Zero-config: all services auto-configure on first start
- Secure by default: AnythingLLM password protection is enabled, and bundled API services auto-generate keys
- HTTPS-ready: optional Caddy overlay provides automatic TLS and binds direct HTTP ports to localhost
- Private: runs locally by default with optional external provider support via LiteLLM
- Flexible: customize models, ports, providers, and API keys with simple env files
- [Lightweight stacks](#lightweight-stacks) for lower memory requirements (as low as ~4.5 GB)
- **GPU acceleration via AMD ROCm** — tuned for the **Ryzen AI Max+ 395** (Strix Halo, gfx1151)
- One-command [installer](#quick-start-amd-rocm--recommended) that checks hardware, sets up the firewall, and pulls the default model
- [Modern status dashboard](#dashboard) — see what's online at a glance and jump straight to it
- Multi-arch: `linux/amd64`, `linux/arm64`

## Community

- 📬 [Subscribe for project updates](https://selfhostedstack.beehiiv.com/subscribe?utm_campaign=ai) (1–2 emails/month) — get free AI and VPN deployment guides (PDF)
- 💬 Join the [r/selfhostedstack](https://www.reddit.com/r/selfhostedstack/) community for discussions and showcases
- ⭐ Star the repository if you find it useful — it helps others discover it

Self-Hosted AI Stack is maintained by the author of [Setup IPsec VPN](https://github.com/hwdsl2/setup-ipsec-vpn) (28k+ stars).

## Quick start (AMD ROCm) — recommended

This variant is rebuilt entirely on **upstream images** and targets **AMD GPUs** (tuned for the **Ryzen AI Max+ 395** / Strix Halo). It uses:

- **[Ollama (ROCm)](https://hub.docker.com/r/ollama/ollama)** as the LLM engine with AMD GPU acceleration
- **[Open WebUI](https://github.com/open-webui/open-webui)** as the chat interface (replaces AnythingLLM)
- **[LiteLLM](https://github.com/BerriAI/litellm)** gateway, **MCP Gateway** + **code sandbox** (tools, incl. `run_python`/`run_shell` for self-testing), **PostgreSQL/pgvector**, **Whisper** (STT) and **Embeddings** (TEI)
- a **[modern status dashboard](#dashboard)** showing the live status of every service

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

### Architecture

```mermaid
graph LR
    U["👤 User"] -->|chat| W["Open WebUI<br/>(port 3001)"]
    U -->|status| DASH["Dashboard<br/>(port 8600)"]
    W -->|OpenAI API| L["LiteLLM<br/>(AI gateway, port 4000)"]
    W -->|OpenAPI tools| MO["mcpo<br/>(MCP → OpenAPI)"]
    L -->|routes to| O["Ollama<br/>(ROCm, AMD iGPU)"]
    L -->|tools| M["MCP Gateway<br/>(filesystem, web, time, GitHub)"]
    L -->|tools| S["Code sandbox<br/>(run_python/run_shell)"]
    MO --> M
    MO --> S
    L -->|metadata| DB[("PostgreSQL<br/>+ pgvector")]
    A["🎤 Audio"] --> WH["Whisper<br/>(speech-to-text)"]
    D["📄 Documents"] --> E["Embeddings<br/>(text-to-vectors)"]
    DASH -.->|reads status| SOCK[("Docker socket<br/>(read-only)")]
    VB["Vault-Bridge<br/>(Nextcloud/Obsidian, port 8700)"] -->|rclone sync| VD[("vault-data<br/>(volume)")]
    VD -.->|read-only per default| M
```

**Show credentials**

```bash
./scripts/show-credentials.sh
```

Prints every URL, the LiteLLM master key, the Postgres password, and the MCP API key straight from your `.env` — no `docker exec ... _manage` needed (that only exists in the old `hwdsl2` images, not the upstream images used here). Open WebUI has no seeded password: the **first account** you register at `http://<server-ip>:3001` automatically becomes admin.

### Dashboard

The stack ships a small, self-contained **modern status dashboard** (`dashboard/`). It reads the Docker socket (read-only) and shows in real time **which services are online, which port they run on**, and links straight to them. It refreshes automatically and is available at `http://<server-ip>:8600`.

**Ollama details & model management:** the Ollama tile is twice as wide as the others and has a **"Details"** button opening a popup with:

- **Load models:** a text field for an Ollama library name (`llama3.1:8b`) or a Hugging Face reference (`hf.co/user/repo:tag`) — Ollama accepts both through the same mechanism. **Multiple downloads at once** are supported, each with its own live progress bar.
- **Currently in memory:** the models loaded right now with their (V)RAM footprint, an activity indicator and the time remaining until auto-unload (Ollama has no direct "is a request running right now" API; the dashboard approximates this by detecting when a model's keep-alive time gets extended by a fresh request). Each one has an **"Unload now"** button that frees the memory immediately instead of waiting for the expiry timer — handy when a model is stuck or you need the VRAM for another one. The model stays installed and is simply reloaded on the next call (hence no confirmation prompt).
- **Installed models:** a list of every downloaded model with its size and a "Delete" button (with a confirmation prompt).

Refreshes every 3 seconds while the popup is open.

> ⚠️ **Security note:** this makes the dashboard **write-capable** for the first time (loading/deleting models), not just read-only. Since it's still LAN-only and has no login of its own, anyone on the same network can trigger downloads or delete models. For a single-user home network this is a reasonable tradeoff — if that's not acceptable, put the dashboard behind its own login/reverse proxy (see below), or drop the `dashboard` service entirely.

#### Protecting the dashboard with login/MFA

The dashboard **deliberately has no user management of its own**. Implementing multi-user login, MFA, sessions and device recognition yourself is exactly the kind of code where mistakes turn into real security holes — that calls for a dedicated authentication proxy in front, not a hand-rolled login inside a status script.

The proven route with [Pangolin](https://docs.pangolin.net/) (or equally Authelia/Authentik/Cloudflare Access):

1. Create an **HTTP resource** in the reverse proxy, target `http://<server-ip>:8600` (i.e. `PORT_DASHBOARD`).
2. Set up an **identity provider** or create local users — that's where the individual accounts live.
3. Enable **MFA per user**; sessions and recognition of known devices are handled by the proxy (unknown device → login + MFA, valid session → straight through).
4. Use **access control** to define who may see the resource.
5. Then close off the direct port so nobody can bypass the proxy: `FIREWALL_MODE=lan` in `.env` (or drop the port from the firewall rules).

The same approach fits every other UI without its own login — in particular the Vault-Bridge, the mcpo tool overview, and Syncthing's web UI.

> The inverse also holds: anything that accepts **API calls** (the LiteLLM API, the MCP endpoint) cannot sit behind a browser-based login portal — the sign-in flow blocks those calls. Those services carry their own bearer-key protection; for remote access to them, prefer a client-based/private resource model (VPN/tunnel) over a login portal.

### MCP Gateway (tools for the LLM)

The stack ships **MCP Gateway** — gives you tools like filesystem, web fetch, time (timezone-correct incl. DST, no model mental math), GitHub, search, and database access. The installer wires it up with LiteLLM automatically (step 7/8); the API key is generated and written to `.env` for you.

```bash
./scripts/wire-mcp.sh   # re-run if the mcp container was recreated (new key)
```

#### Managing MCP servers (MCPHub UI)

The `mcp` container runs [MCPHub](https://github.com/samanhappy/mcphub), which ships its own web UI for managing MCP servers — reachable at `http://<server-ip>:3000` (or via the "MCP Gateway" dashboard tile):

- **Inspect servers:** which MCP servers are running, which tools each provides, live logs
- **Enable/disable:** switch off individual servers or individual tools without deleting them
- **Add new ones:** register further MCP servers — applied by hot-reload, no container restart

Sign in with the `admin` user from `/var/lib/mcp/mcp_settings.json`. The same port also serves the `/mcp` endpoint for direct MCP clients (Claude Desktop, Cursor, …), protected by the bearer key from `.env`.

> **Restart `mcpo` after every change to the MCP servers** (`./scripts/restart-mcp.sh --mcpo-only`) — otherwise `mcpo` keeps serving the old tool list and Open WebUI won't see the change.

Configurable via `.env`: `PORT_MCP` (default `3000`). `install.sh` opens the port **for the LAN only, regardless of firewall mode**: the UI and endpoint are protected (login / bearer key respectively), but they grant access to every tool including write access to the vault.

### Code sandbox (`run_python` / `run_shell` for the LLM)

Alongside MCP Gateway, the stack ships a dedicated **code sandbox** (`sandbox-mcp/`) so the model can **test code it writes, catch errors, and iterate** instead of handing you untested code. Two tools, exposed through the same LiteLLM MCP mechanism:

- `run_python(code)` — runs Python code
- `run_shell(command)` — runs a shell command

**How isolation works:** every single call spins up a **brand-new, isolated, throwaway container** — no network access, read-only filesystem (only `/tmp` is writable), memory/CPU/process limits, no root, all Linux capabilities dropped, a timeout (15s default, 60s max). The container is deleted immediately after each run — there's no state to reset: every call starts from zero, guaranteed.

> ⚠️ **Security note:** for the sandbox service to spin up a fresh container per call, it needs access to the host's **Docker socket** (`/var/run/docker.sock`). That's powerful — anyone who can reach this internal service can, in principle, start arbitrary containers on the host. It is therefore deliberately reachable **internally only**, with no port published outside the Docker network. For a single-user setup on your own LAN this is a reasonable tradeoff; if you don't want this capability, just remove the `sandbox-mcp` service (and the matching `code_sandbox` entry in `litellm/config.yaml`) and restart the stack.

Configurable via `.env`: `SANDBOX_IMAGE` (the sandbox's base image, default `python:3.12-slim`), `SANDBOX_DEFAULT_TIMEOUT`, `SANDBOX_MAX_TIMEOUT`, `SANDBOX_MEM_LIMIT`, `SANDBOX_TMPFS_SIZE` (size of the writable `/tmp`, default `64m`), `SANDBOX_NETWORK` (default `none`; set e.g. `bridge` if the code needs internet access — you then lose the network-isolation protection).

#### More languages in the sandbox

With the default image `python:3.12-slim` the sandbox can run **Python and shell** (Debian base, so bash and the usual command-line tools) — nothing else. No Java, no Node, no compilers. When a model claims it can do "C++, Rust, JS, if installed", that's a guess; what actually counts is what's in the runner image.

The repo therefore ships an optional multi-language runner image (`sandbox-mcp/runner-multilang.Dockerfile`) — Python, Node/npm, Java (JDK), Go, gcc/g++/make, plus git/curl/jq:

```bash
docker build -f sandbox-mcp/runner-multilang.Dockerfile \
  -t ai-stack-sandbox-runner:multilang sandbox-mcp/
```

Optionally add **PowerShell** (`pwsh`) — costs ~200 MB and comes from Microsoft's package source, hence off by default:

```bash
docker build --build-arg WITH_POWERSHELL=1 \
  -f sandbox-mcp/runner-multilang.Dockerfile \
  -t ai-stack-sandbox-runner:multilang sandbox-mcp/
```

Then in `.env`:

```bash
SANDBOX_IMAGE=ai-stack-sandbox-runner:multilang
SANDBOX_MEM_LIMIT=2g
SANDBOX_TMPFS_SIZE=1g
SANDBOX_DEFAULT_TIMEOUT=60
SANDBOX_MAX_TIMEOUT=180
```

```bash
docker compose -f docker-compose.rocm.yml up -d sandbox-mcp
```

> ⚠️ **The raised limits are not optional.** `javac`, `go build` and `g++` fail reliably against the defaults (256 MB RAM, 64 MB `/tmp`, 15s) — swapping the image alone is not enough.

**Known limits of this approach:**

- **No network** (default `SANDBOX_NETWORK=none`): `npm install`, `pip install`, `go get` and Gradle dependencies won't work. Standard library and whatever is baked into the image only. If you need more, set `SANDBOX_NETWORK=bridge` and give up the isolation.
- **No state between calls** — every call is a fresh container. Multi-stage builds that rely on intermediate state won't work.
- **Package versions come from Debian stable** and are correspondingly conservative (e.g. Node 18, Go 1.19, JDK 17). Adjust the Dockerfile for newer ones.
- **PowerShell** is not included by default but can be enabled at build time (see above). Windows-specific cmdlets (registry, WMI, Active Directory, …) naturally still don't exist on Linux.
- **Android app development doesn't work in the sandbox** — SDK, Gradle and emulator far exceed what a throwaway container without network can do. There's a dedicated service for that, see the next section.

### Android development (`android-mcp`)

The throwaway sandbox isn't enough for Android: Gradle pulls dependencies from the network, a build takes minutes rather than seconds, and without a persistent cache every run would start from scratch. The stack therefore ships a **dedicated service** for it (`android-mcp/`) where builds run **directly in the container** — which also spares it the Docker socket access the code sandbox needs.

Included: **JDK 21**, the **Android SDK** (command-line tools, platform-tools, build-tools, platform android-34) and **Gradle**. Tools exposed to the model:

| Tool | Purpose |
|---|---|
| `list_projects()` | List projects in the workspace |
| `create_project(name, package_name)` | Create a new, buildable Java/Gradle project (manifest, MainActivity, example test, Gradle wrapper) |
| `gradle(project, args)` | Run a Gradle task — `assembleDebug`, `test`, `clean`, `tasks`, … |
| `sdk_packages()` | Show installed SDK packages |
| `install_sdk_package(package)` | Install another SDK package, e.g. `platforms;android-35` |

Sources live in the `android-workspace` volume, which is **also mounted in the `mcp` container** at `/workspace`. That lets the model edit the code with the **filesystem tools** and build it with `gradle` — writing and building hit the same files.

**Typical chat flow:** "Create an Android project `MyApp`" → `create_project` → model edits `MainActivity.java` via the filesystem tool → "build it" → `gradle(project="MyApp", args="assembleDebug")` → on errors the model reads the Gradle output and fixes it itself.

**Build and start:**

```bash
docker compose -f docker-compose.rocm.yml up -d --build android-mcp
./scripts/wire-mcp.sh    # adds /workspace to the filesystem tool
```

> ⚠️ **The image is large (~6–8 GB) and the first build takes a while** (Android SDK). The first Gradle run of a project also pulls Gradle and all dependencies — after that the cache in the `android-gradle` volume kicks in. If you don't need Android development, drop the service entirely (and remove the `android_build` entry from `mcpo/config.template.json`).

**Limits:**

- **No emulator, no running the app.** Building, compiling and unit testing happen in the container; trying out the APK needs a real device. An emulator would need `/dev/kvm` inside the container and is fragile in practice.
- **No `adb` access to your devices** — those hang off your machine, not the server.
- **Network access is intentional here** (Gradle needs it) — unlike the code sandbox. Gradle build scripts are executable code, so this service is about as powerful as the sandbox, just with internet. Like the sandbox it is therefore reachable **internally only**, with no published port.
- **The project template is deliberately minimal** (Java, no Kotlin/Compose) — fewer version dependencies between Gradle, AGP and Kotlin that have to line up. Kotlin/Compose can be added within the project itself.

Configurable via `.env`: `ANDROID_DEFAULT_TIMEOUT` (default `600` s), `ANDROID_MAX_TIMEOUT` (`1800` s), `ANDROID_COMPILE_SDK` (`34`), `ANDROID_MIN_SDK` (`24`). SDK/Gradle/AGP versions are build arguments in `android-mcp/Dockerfile`.

### Enable the tools in Open WebUI (mcpo)

**Important:** Open WebUI doesn't speak raw MCP — only **OpenAPI**. The stack ships `mcpo` (the Open WebUI team's own official MCP-to-OpenAPI proxy) to bridge MCP Gateway and the code sandbox into a format Open WebUI understands directly. `scripts/wire-mcp.sh` sets this up automatically too.

How to connect the tools in Open WebUI:

1. **Admin panel** (gear icon, then **Settings → Tools**, or on some versions **Workspace → Tools → External Tool Servers**)
2. Add a new tool server, URL: **`http://mcpo:8000/mcp_gateway`** (filesystem, web, time, GitHub, search, DB)
3. Add a second one, URL: **`http://mcpo:8000/code_sandbox`** (`run_python`, `run_shell`)
4. Optionally a third, URL: **`http://mcpo:8000/android_build`** (create/build/test Android projects — only needed if you run the `android-mcp` service)
5. In chat: use the tool icon below the input box to enable the tools you want for that conversation

```bash
docker logs mcpo          # is mcpo running, are both servers loaded?
docker logs sandbox-mcp   # is the code sandbox running?
docker logs litellm | grep -i mcp   # does LiteLLM itself also see the MCP servers?
```

> **Note:** Exact menu paths and behavior can differ slightly by Open WebUI version (a fast-moving area) — verify together after deploy that the tools are actually invoked in chat.

> ⚠️ **Known limitation (reproduced, as of this doc):** For models routed through a **LiteLLM** connection, Open WebUI correctly formulates a tool call but sometimes never actually dispatches it — the raw call JSON shows up verbatim as visible text in the reply instead. Over a **direct Ollama connection** (Admin → Settings → Connections → "Ollama API") the same call ran reliably and was actually executed in testing. If tools only ever return text instead of real results for you: try switching to a direct Ollama connection to check if that's the difference.

#### Checklist: enabling tools per model

Tool settings in Open WebUI apply **per model**, not globally — so a newly pulled model always starts without tools, even if another model has been working for ages. Work through these five points under **Workspace → Models → `<model>` → Edit**:

| # | Setting | Value | Why |
|---|---|---|---|
| 1 | **Tools** | "MCP Gateway" ✓ (+ "Code Sandbox") | Without the checkbox the model doesn't know the tools exist at all |
| 2 | **Capabilities → Built-in Tools** | **off** | Otherwise the model gets Open WebUI's own note/calendar tools instead and ignores the MCP ones |
| 3 | **Advanced Params → Function Calling** | **Default** (not "Native") | "Native" assumes reliable tool-calling in the model; smaller local models often fail at it silently |
| 4 | **Advanced Params → `num_ctx` (Ollama)** | **at least `16384`** | Ollama's small default context window truncates the tool list — the model then sees only the first few tools and treats the rest as non-existent |
| 5 | **System prompt** | Instruction to use tools (example below) | Stops the model from prematurely answering "I don't have access to that" instead of trying |

Example for point 5:

```
You have access to external tools. Before saying you can't do something,
don't know something, or have no access, ALWAYS check first whether one of
your available tools could solve the task — and then call it. Questions about
files/notes/knowledge base → filesystem tools; current information/web pages
→ web tools; date/time/timezones → time tool (never compute it yourself);
testing code → sandbox tools. If you don't know the path or parameters, work
your way there in several steps (list/search first, then read) instead of
giving up. Never claim to be an isolated AI without access — that is false
here. If a tool call fails, state the actual error message.
```

> **Note:** A model claiming a tool doesn't exist is **not** reliable evidence. Such self-reports are routinely fabricated — when in doubt, check the tool overview (below) for what's actually there.

#### Tool overview in the browser (mcpo)

mcpo ships a Swagger UI that **authoritatively** shows which tools are available to the models — including parameters, and directly testable without a model in the loop:

```
http://<server-ip>:8800/mcp_gateway/docs     # filesystem, web fetch, time, …
http://<server-ip>:8800/code_sandbox/docs    # run_python, run_shell
```

(Also available as the "mcpo" dashboard tile.) The same list on the command line:

```bash
docker exec mcp curl -s http://mcpo:8000/mcp_gateway/openapi.json \
  | grep -oE '"/[a-zA-Z0-9_-]+"' | sort -u
```

And testing a single tool directly, with no model involved — the fastest way to answer "is it the backend or the model?":

```bash
docker exec mcp curl -s -X POST http://mcpo:8000/mcp_gateway/filesystem-list_directory \
  -H "Content-Type: application/json" -d '{"path":"/vault"}'
```

Configurable via `.env`: `PORT_MCPO` (default `8800`). `install.sh` opens the port **for the LAN only, regardless of firewall mode**: mcpo has no authentication of its own, and its tools (`filesystem-write_file` and friends) would give access to the vault. Open WebUI reaches mcpo container-internally anyway and doesn't need the published port.

#### Time tool (timezones without model mental math)

Language models are, in practice, unreliable at timezone conversion — they forget daylight saving time, miscalculate, or invent a plausible-sounding but wrong time without ever calling a tool at all. So the stack ships its own small tool (`mcp-tools/get_time.py`, part of the `mcp_gateway` server, no extra entry needed in Open WebUI): it computes with Python's `zoneinfo` (standard library, correctly DST-aware) instead of letting the model guess. It accepts a list of IANA timezones (e.g. `Asia/Bangkok`, `Europe/Berlin`, `America/Vancouver`) so multi-part questions ("what time is it in X and Y?") can be answered reliably in a single call.

Example prompt: *"Use the time tool for Asia/Bangkok and Europe/Berlin."* As with the fetch tool, a matching system prompt helps nudge the model to use it unprompted whenever asked about the time.

`scripts/wire-mcp.sh` idempotently adds `filesystem` and `time` to `mcp_settings.json` if the image didn't register them on first start (a known gap, see commit history) — just re-run it if `docker exec mcp cat /var/lib/mcp/mcp_settings.json` is missing either entry.

### Vault-Bridge (Obsidian/Nextcloud as knowledge for the LLM)

You can connect an **Obsidian vault hosted on Nextcloud** to the stack — not by "building AI into Obsidian," but the other way around: **every** client wired to LiteLLM (Open WebUI, and in future e.g. Claude) gets read access to your own knowledge through the MCP Gateway filesystem tool. For this, the stack ships a `vault-bridge` service — its own **web-configurable** bridge, no manual `.env` editing required.

**Setup:**

1. In Nextcloud, create an **app password** (Profile → Security → "Create new app password") — don't use your main account password.
2. Open the Vault-Bridge UI: `http://<server-ip>:8700` (or via the "Vault-Bridge" tile on the dashboard).
3. Enter the server URL, username, app password, and a sync interval. For the vault path, either type it directly (e.g. `Notes/ObsidianVault`) or click the folder-browse button to navigate your own Nextcloud folder structure instead of risking a typo. Then click **"Connect & sync"**.

Once the first sync succeeds, the **MCP Gateway filesystem tool sees the vault automatically** — the bridge and MCP Gateway share the same Docker volume (`vault-data`), so `mcp` never needs to be restarted. No extra setup in Open WebUI is needed either: it's the same `mcp_gateway` tool server you already connected above (see "Enable the tools in Open WebUI").

**How it works under the hood:** `vault-bridge` uses [`rclone`](https://rclone.org/) in **sync** mode, not mount mode — it pulls files over WebDAV on an interval instead of live-mounting the vault via FUSE. That avoids needing `/dev/fuse` access or extended container privileges, making it the safer option; for a knowledge base, periodic sync is plenty — millisecond-live updates aren't needed.

> ⚠️ **Security note:** the Nextcloud app password is stored on the server (its own volume, `vault-bridge-data`) so the bridge can re-sync on its own. Before being written, it's **obscured** with `rclone obscure` — that is **not real encryption**, just protection against casual reading. Always use a dedicated app password (revocable independently of your main password at any time in Nextcloud), never your main password. By default, the MCP Gateway filesystem tool mounts the vault **read-only** (`:ro`) — even if a client tried to write, the Docker mount itself blocks it, not just the app logic.

#### Write access for the AI (two-way sync)

By default the connection is **read-only**: Nextcloud → local → MCP Gateway. If you want the AI to also create/edit notes through the MCP filesystem tool, with those changes flowing back to Nextcloud, you need **two** switches set together:

1. In the Vault-Bridge UI: check **"Enable two-way sync"**, then click "Connect & sync" again. Under the hood this switches from `rclone sync` (one-way) to [`rclone bisync`](https://rclone.org/bisync/) (two-way) — on the first run in this mode the bridge automatically performs the required one-time `--resync` baseline. Conflicts (a file changed on both sides) are never silently overwritten: rclone keeps both versions, renamed with a `.path1`/`.path2` suffix, for you to review manually. (The `apt`-installed rclone in this image is older than the current docs on rclone.org — it doesn't support newer `bisync` flags like `--conflict-resolve` or `--fast-list`, so we deliberately don't use them.)
2. In `.env`: set `MCP_VAULT_MOUNT_MODE=rw`, then run `docker compose -f docker-compose.rocm.yml up -d mcp mcpo` (default is `ro`). Restarting **both** matters: `mcpo` holds a live session to `mcp` — recreate only `mcp` and that session breaks, causing tool calls from Open WebUI to fail with `"MCP session is not available"` until `mcpo` is restarted too. The same rule applies to **any** restart/recreation of `mcp` (e.g. after an image update) — always restart `mcpo` along with it.

> ⚠️ Setting only **one** of the two switches isn't enough and can cause silent data loss: `rw` alone without two-way sync means the AI can write locally, but the next automatic one-way sync from Nextcloud silently overwrites/deletes it again. Two-way sync alone without `rw` means the AI still can't write at all (Docker blocks it at the mount level). Always enable both together.

**Known limitation of the `mcp` gateway image:** on some installs, `hwdsl2/mcp-gateway` fails to auto-register the `filesystem` tool on its very first start, even though `MCP_SERVERS=fetch,filesystem` is set correctly (`docker logs mcp` then shows only a "connected client for server: fetch" line, none for `filesystem`). Check with `docker exec mcp cat /var/lib/mcp/mcp_settings.json` — if the `filesystem` entry is missing under `mcpServers`, add it manually:
```bash
docker exec mcp node -e "
const fs = require('fs');
const path = '/var/lib/mcp/mcp_settings.json';
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
data.mcpServers.filesystem = { command: 'npx', args: ['-y', '@modelcontextprotocol/server-filesystem', '/vault'] };
fs.writeFileSync(path, JSON.stringify(data, null, 2));
"
docker compose -f docker-compose.rocm.yml restart mcp mcpo
```

Configurable via `.env`: `PORT_VAULT_BRIDGE` (default `8700`), `MCP_VAULT_MOUNT_MODE` (`ro`/`rw`, default `ro`), plus `MCP_SERVERS`/`MCP_FILESYSTEM_DIRS` on the `mcp` service if you want to add further MCP tools or directories.

### Syncthing (alternative to Vault-Bridge)

If your vault is already synced by a **dedicated Nextcloud client** running on another device (e.g. the official Windows desktop client), that client and Vault-Bridge can get in each other's way — two independent two-way sync engines operating on the same files lead to locks, conflicts, and aborted sync runs. [Syncthing](https://syncthing.net/) sidesteps this by syncing **directly** between your devices, with no Nextcloud detour at all — and it handles conflicts safely: for a file changed on both sides, it **never** silently overwrites, but instead creates a second file named `.sync-conflict-<timestamp>-<device>`.

**Setup:**

1. Start/update the stack (`docker compose -f docker-compose.rocm.yml up -d syncthing`) — the web UI runs at `http://<server-ip>:8384` (or via the "Syncthing" tile on the dashboard).
2. **Set a password immediately:** Settings → GUI → Authentication — the UI ships with **no** password by default.
3. Install the [Syncthing client](https://syncthing.net/downloads/) on your other device (Windows/Mac/Linux) and open its web UI too.
4. On both sides, copy the device ID under "This Device" and add it on the other device as a "Remote Device".
5. On the server, share a new folder pointing at `/var/syncthing/vault` (the same `vault-data` volume the MCP Gateway filesystem tool also sees) — accept it on the other device and pick the local target folder there (e.g. your existing Obsidian vault folder).

> ⚠️ Use **only one** of the two (Vault-Bridge **or** Syncthing) for the same folder — never both at once, for the same reason a Nextcloud client + Vault-Bridge got in each other's way. If you switch to Syncthing: click "Disconnect" in the Vault-Bridge UI so it stops touching the same folder.

Configurable via `.env`: `PORT_SYNCTHING_GUI` (default `8384`). The sync/discovery ports (22000 tcp+udp, 21027/udp) are fixed and are opened by `install.sh` for the LAN only regardless of firewall mode (no reason to expose them publicly).

### Register models with LiteLLM

New models get registered with LiteLLM **automatically** — whether you pull them via the [dashboard's model manager](#dashboard) or directly with `docker exec ollama ollama pull …`. The dashboard reconciles in the background roughly every 60 seconds, registering any installed Ollama model LiteLLM doesn't know yet under `ollama/<model>` (idempotent — already-registered ones are skipped), and triggers an immediate sync right after a dashboard-initiated download instead of waiting for the next interval. Status ("✓ auto-synced with LiteLLM …") is shown in the dashboard's "Load models" popup.

This needs `LITELLM_MASTER_KEY` to reach the dashboard container (`install.sh`/`.env` do this automatically); without a key the popup shows "⚠ automatic LiteLLM registration inactive" and you register manually instead:

```bash
docker exec ollama ollama pull qwen2.5:14b
./scripts/sync-ollama-models.sh
```

The script stays available as a manual fallback (e.g. for instant control instead of waiting up to 60s) and is likewise **idempotent**.

### Useful commands

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

### Uninstall

The install script can also clean up — both the new ROCm stack and the **old** stack (AnythingLLM/`hwdsl2` images):

```bash
sudo ./install.sh --uninstall   # remove containers & networks, keep data (volumes)
sudo ./install.sh --purge       # remove EVERYTHING: models, chats, database and .env too
```

`--purge` is irreversible and asks for confirmation first (type `loeschen`; add `-y` to skip the prompt). Firewall rules are left untouched.

> The sections below describe the **original CPU/NVIDIA stack** (the `hwdsl2/*` images and AnythingLLM). For AMD, use the ROCm quick start above.

## Included services

| Service | Role | Default port |
|---|---|---|
| **[Ollama (LLM)](https://github.com/hwdsl2/docker-ollama)** | Runs local LLM models (llama3, qwen, mistral, etc.) | `11434` |
| **[AnythingLLM](https://github.com/mintplex-labs/anything-llm)** | Web-based chat UI — password-protected by default | `3001` |
| **[LiteLLM](https://github.com/hwdsl2/docker-litellm)** | AI gateway with Admin UI — routes requests to Ollama and 100+ providers | `4000` |
| **[Embeddings](https://github.com/hwdsl2/docker-embeddings)** | Converts text to vectors for semantic search and RAG | `8000` |
| **[Whisper (STT)](https://github.com/hwdsl2/docker-whisper)** | Transcribes spoken audio to text | `9000` |
| **[WhisperLive (real-time STT)](https://github.com/hwdsl2/docker-whisper-live)** | Real-time speech-to-text transcription over WebSocket | `9090` |
| **[Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro)** | Converts text to natural-sounding speech | `8880` |
| **[MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway)** | Provides MCP tools (filesystem, fetch, GitHub, search, databases) to AI clients | `3000` |
| **[Docling](https://github.com/hwdsl2/docker-docling)** | Converts documents (PDF, DOCX, etc.) to structured text/Markdown | `5001` |

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

> **PostgreSQL credentials:** Fresh installs and existing default installs are handled automatically. If you previously set a custom database password, see [PostgreSQL credentials](#postgresql-credentials) before starting.

**Pull a model** (required before making LLM requests):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

Run the health check to verify all services are working:

```bash
./stack-check.sh
```

> **Tip:** On first start, services may take a few minutes to initialize. If any checks fail, wait and run `./stack-check.sh` again. Use `docker compose logs` to check progress.

For detailed troubleshooting, see the [Troubleshooting](docs/troubleshooting.md) guide.

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

> **Tip:** When exposing AnythingLLM beyond `localhost` or a trusted LAN, use the included Caddy HTTPS overlay so the password is encrypted in transit and direct HTTP ports are bound to localhost. See [Internet-facing deployments](#internet-facing-deployments) below.

**Access the LiteLLM Admin UI:**

Open `http://<server-ip>:4000/ui` in your browser. Log in with username `admin` and your LiteLLM master key as the password. The UI provides virtual key management, spend tracking, and model configuration.

> **Tip:** In the Admin UI, click **Playground** in the left menu. Select a local model (e.g., `ollama-chat/llama3.2:3b`) from the dropdown and start chatting — a quick way to verify your local LLM is working end-to-end.

**Stop the stack:**

```bash
# Stop and remove all containers (data is preserved in Docker volumes)
docker compose down
```

## GPU acceleration (AMD ROCm)

For AMD GPUs (e.g. the **Ryzen AI Max+ 395** / Strix Halo), use the ROCm compose file — most easily via the [installer](#quick-start-amd-rocm--recommended), or manually:

```bash
docker compose -f docker-compose.rocm.yml up -d --build
```

The `ollama` service uses the official `ollama/ollama:rocm` image and gets the GPU passed through via `/dev/kfd` and `/dev/dri`. `--build` makes sure the locally-built `sandbox-mcp` service (code sandbox) is actually built instead of mistakenly pulled from a registry.

**Requirements:**

- AMD GPU with the `amdgpu` kernel module loaded and **ROCm** (or `amdgpu-dkms`) installed
- The devices `/dev/kfd` and `/dev/dri/renderD*` must be present
- Your user must be in the `video` and `render` groups (the install script handles this)

For the **Ryzen AI Max+ 395** (iGPU `gfx1151`) the stack sets `HSA_OVERRIDE_GFX_VERSION=11.5.1` in case ROCm doesn't detect the iGPU directly. You can adjust this value in `.env`. Thanks to the large unified memory, the iGPU can load very large models.

> **Tip:** The [installer](#quick-start-amd-rocm--recommended) (`./install.sh`) checks all of this automatically and reports what's missing. If the kernel driver is missing, it **offers to install `amdgpu-dkms`** (just the kernel driver — the ROCm libraries ship inside the container image). Force it with `sudo ./install.sh --install-drivers`, skip it with `--skip-drivers`. For a check without changes: `./install.sh --check-only`.

> **Note:** After a fresh driver install a **reboot** may be required for `/dev/kfd` to appear. Then just run the installer again. If the suggested ROCm version doesn't match your distribution, override it with `ROCM_VERSION=6.x.y sudo ./install.sh --install-drivers`.

## Lightweight stacks

Don't need the full stack? Use a pre-configured subset from the `stacks/` folder:

> **Note:** The lightweight stacks share default container names, ports, and Docker volume names. Run one stack variant at a time with the default compose files; stop the current variant before switching to another. To combine capabilities, use the full stack or customize Compose project names, container names, ports, and volumes.

| Stack | Services | Memory | Use case |
|---|---|---|---|
| **[chat-ui](stacks/chat-ui/)** | Ollama + LiteLLM + AnythingLLM | ~5 GB | Web-based ChatGPT-like chat interface |
| **[voice-pipeline](stacks/voice-pipeline/)** | Whisper + Ollama + LiteLLM + Kokoro | ~6 GB | Speech-to-text → LLM → text-to-speech |
| **[voice-chat](stacks/voice-chat/)** | Whisper + Ollama + LiteLLM + Kokoro + AnythingLLM | ~6.5 GB | Chat UI with voice input/output |
| **[rag-pipeline](stacks/rag-pipeline/)** | Ollama + LiteLLM + Embeddings | ~5 GB | Semantic search + LLM Q&A |
| **[rag-pipeline-full](stacks/rag-pipeline-full/)** | Ollama + LiteLLM + Embeddings + Docling | ~6 GB | Document parsing + semantic search + LLM Q&A |
| **[code-assistant](stacks/code-assistant/)** | Ollama + LiteLLM + MCP Gateway + Embeddings | ~5 GB | AI coding with tools + semantic code search |
| **[ai-tools](stacks/ai-tools/)** | Ollama + LiteLLM + MCP Gateway | ~5 GB | AI coding assistant with tool access |
| **[chat-only](stacks/chat-only/)** | Ollama + LiteLLM | ~4.5 GB | Minimal local ChatGPT replacement |

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

## Connect MCP Gateway to LiteLLM

LiteLLM and MCP Gateway are **automatically wired** when using the compose files in this repository — no manual key setup is needed.

API keys are shared automatically between services via Docker shared volumes:

- Ollama generates an API key on first start and copies it to a shared volume
- MCP Gateway does the same
- LiteLLM reads both keys from the shared volumes on startup

The `LITELLM_MCP_URL=http://mcp:3000/mcp` and `LITELLM_OLLAMA_BASE_URL=http://ollama:11434` environment variables are pre-configured in the compose files, so all services are connected automatically with a single `docker compose up -d`.

Once connected, AI clients that call LiteLLM can use MCP tools (filesystem, fetch, GitHub, etc.) directly through the LiteLLM proxy.

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

## MCP tools example

Use MCP Gateway to give your AI assistant access to files, web, and GitHub:

MCP Gateway is internal to the Docker network by default. Before using `http://localhost:3000/mcp` from a host-side AI client or host-side `curl`, uncomment the `3000:3000/tcp` port mapping for the `mcp` service in `docker-compose.yml` and restart it.

```bash
MCP_KEY=$(docker exec mcp mcp_manage --getkey)

# Use MCP endpoint with an AI client (e.g., Cline in VS Code)
# Set the MCP server URL: http://localhost:3000/mcp
# Set Authorization header: Bearer <api_key>

# Or test the MCP endpoint directly with an initialize request
curl -s http://localhost:3000/mcp \
    -X POST \
    -H "Authorization: Bearer $MCP_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

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

## Internet-facing deployments

By default, all services listen over plain HTTP. For internet-facing deployments, use the included Caddy overlay to add automatic HTTPS. In proxy mode, Caddy is the only public listener on ports `80` and `443`; the direct AnythingLLM and LiteLLM ports are rebound to `127.0.0.1`.

Prerequisites:

- Docker Compose `2.24.4+` (required for the proxy overlay's port override)
- A DNS `A`/`AAAA` record for your domain pointing to this server
- Inbound `80/tcp`, `443/tcp`, and ideally `443/udp` open in your firewall/security group
- No other service already using ports `80` or `443` on the host

**CPU stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

**CUDA stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.cuda.yml -f docker-compose.proxy.yml up -d
```

Open `https://chat.example.com` (replace with your `DOMAIN`) to access AnythingLLM. In proxy mode, `http://127.0.0.1:3001` and `http://127.0.0.1:4000/ui` remain available on the host, but the direct `3001` and `4000` ports are not reachable from outside the server.

The standard compose files publish LiteLLM on port `4000`. The proxy overlay changes that direct port to localhost-only, and the included Caddyfile routes only AnythingLLM by default. Uncommenting the optional LiteLLM hostname block exposes LiteLLM through Caddy, so keep the LiteLLM master key secret.

Troubleshooting:

```bash
docker logs ai-stack-caddy
# Use the same -f files you used to start the stack
docker compose -f docker-compose.yml -f docker-compose.proxy.yml ps
```

If Caddy reports an unknown `request_body` directive, pull the current `caddy:2` image and restart the overlay.

For older Docker Compose versions or Podman, use a host-based reverse proxy instead: bind direct HTTP ports to localhost in the compose file (for example, `"127.0.0.1:3001:3001/tcp"` and `"127.0.0.1:4000:4000/tcp"`) and proxy to those localhost ports. For stack-specific Caddy and nginx examples, see the [Chat UI manual reverse proxy section](stacks/chat-ui/#manual-reverse-proxy).

When exposing services to the internet, use the generated API keys where present. For existing no-key deployments, set API keys via the relevant env files before publishing those services.

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

For restore instructions, server migration, and the full pre-upgrade checklist, see the [Backup and Restore](docs/backup-restore.md) guide.

## PostgreSQL credentials

Fresh Docker Compose installs generate a random PostgreSQL password automatically and store it in the `ai-stack-shared` volume. Existing default installs continue to use the legacy `litellm` database password for compatibility.

If you previously customized the database password, set `LITELLM_POSTGRES_PASSWORD` in your shell environment to that current password before running `docker compose up -d`, or keep an explicit `LITELLM_DATABASE_URL` override in `litellm.env`.

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

## License

Copyright (C) 2026 Lin Song   
This work is licensed under the [MIT License](https://opensource.org/licenses/MIT).

This project is an independent Docker configuration and is not affiliated with, endorsed by, or sponsored by Docker, Inc., Ollama, Berri AI (LiteLLM), Hugging Face, hexgrad (Kokoro), OpenAI, SYSTRAN, or MCPHub. Docker is a trademark or registered trademark of Docker, Inc.
