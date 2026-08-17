# Code sandbox

Letting the model run and test code — isolation, workspace and more languages.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/code-sandbox.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · **Code sandbox** · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Code sandbox (`run_python` / `run_shell` for the LLM)

Alongside MCP Gateway, the stack ships a dedicated **code sandbox** (`sandbox-mcp/`) so the model can **test code it writes, catch errors, and iterate** instead of handing you untested code. Three tools, exposed through the same LiteLLM MCP mechanism:

- `run_python(code)` — runs Python code
- `run_shell(command)` — runs a shell command (**bash**, not `sh` — models almost always write bash syntax)
- `run_script(script, interpreter, args)` — runs a **complete, multi-line script**: bash, sh, python3, node, ruby, perl, php or pwsh, optionally with arguments

> **Why `run_script` in addition to `run_shell`?** Squeezing a whole script into a one-liner regularly fails on quoting and newlines — exactly where models get stuck and then try dozens of variants. `run_script` takes the content as-is (transferred base64-encoded internally so quotes, `$`, backslashes and non-ASCII characters arrive intact), writes it to a file and invokes the chosen interpreter on it.

> ⚠️ **No terminal in the sandbox:** `tput cols`/`tput lines` return no real values there, and colour escapes appear as raw text in the output. Both are normal and say nothing about how the script behaves in the user's terminal — scripts should provide a fallback for `tput` (`$(tput cols 2>/dev/null || echo 80)`).

**How isolation works:** every single call spins up a **brand-new, isolated, throwaway container** — no network access, read-only filesystem, memory/CPU/process limits, no root, all Linux capabilities dropped, a timeout (15s default, 60s max). The container is deleted immediately after each run.

**Two writable areas — the difference matters:**

| Path | Behaviour | For |
|---|---|---|
| **`/work`** | **persists across calls** (its own `sandbox-work` Docker volume), and is the working directory | Creating test files and testing against them in a later call, iterating on scripts |
| `/tmp` | wiped on every call | Throwaway intermediates |

> **Why `/work` exists at all:** without a persistent area, multi-step work is impossible — a model that creates test directories and wants to test against them in the next call simply can't find them any more and spins in circles (observed exactly like that in practice). Tasks of the form "write a script **and test it**" only work with this.

> ⚠️ **Security note:** `/work` deliberately outlives calls — so code from one call can leave files behind for later ones. Isolation towards the host and the rest of the stack is unchanged (no network, no root, no access to the vault or other volumes). To wipe the area: `docker volume rm sandbox-work` (stop the service first).

> ⚠️ **Security note:** for the sandbox service to spin up a fresh container per call, it needs access to the host's **Docker socket** (`/var/run/docker.sock`). That's powerful — anyone who can reach this internal service can, in principle, start arbitrary containers on the host. It is therefore deliberately reachable **internally only**, with no port published outside the Docker network. For a single-user setup on your own LAN this is a reasonable tradeoff; if you don't want this capability, just remove the `sandbox-mcp` service (and the matching `code_sandbox` entry in `litellm/config.yaml`) and restart the stack.

Configurable via `.env`: `SANDBOX_IMAGE` (the sandbox's base image, default `python:3.12-slim`), `SANDBOX_DEFAULT_TIMEOUT`, `SANDBOX_MAX_TIMEOUT`, `SANDBOX_MEM_LIMIT`, `SANDBOX_TMPFS_SIZE` (size of the ephemeral `/tmp`, default `64m`), `SANDBOX_WORK_VOLUME` (volume backing the persistent `/work` area, default `sandbox-work`), `SANDBOX_NETWORK` (default `none`; set e.g. `bridge` if the code needs internet access — you then lose the network-isolation protection).

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
