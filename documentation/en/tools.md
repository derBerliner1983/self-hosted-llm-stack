# Tools for the LLM (MCP)

MCP Gateway, wiring it into Open WebUI, and the per-model checklist.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/werkzeuge.md)

**Documentation:** [Installation & getting started](installation.md) · [Architecture & services](architecture.md) · **Tools for the LLM (MCP)** · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## MCP Gateway (tools for the LLM)

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

## Enable the tools in Open WebUI (mcpo)

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
testing code → sandbox tools; creating/building Android projects → the
Android tools (NOT the sandbox). If you don't know the path or parameters,
work your way there in several steps (list/search first, then read) instead
of giving up.

Work deliberately rather than by trial and error: read your tools'
descriptions and pick the right one, instead of rephrasing the same question
at an unsuitable tool over and over. If a tool reports that something does
not exist or is not installed, that is an answer — do not then try dozens of
path or command variants; check whether a DIFFERENT tool is responsible, and
otherwise tell the user plainly what is missing. More than a few attempts at
the same sub-question means you are looking in the wrong place.

Never claim to be an isolated AI without access — that is false here. If a
tool call fails, state the actual error message.
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

## Connect MCP Gateway to LiteLLM

LiteLLM and MCP Gateway are **automatically wired** when using the compose files in this repository — no manual key setup is needed.

API keys are shared automatically between services via Docker shared volumes:

- Ollama generates an API key on first start and copies it to a shared volume
- MCP Gateway does the same
- LiteLLM reads both keys from the shared volumes on startup

The `LITELLM_MCP_URL=http://mcp:3000/mcp` and `LITELLM_OLLAMA_BASE_URL=http://ollama:11434` environment variables are pre-configured in the compose files, so all services are connected automatically with a single `docker compose up -d`.

Once connected, AI clients that call LiteLLM can use MCP tools (filesystem, fetch, GitHub, etc.) directly through the LiteLLM proxy.

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
