# LibreChat (second chat UI)

An alternative to Open WebUI — speaks MCP directly, without the mcpo detour.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/librechat.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · **LibreChat (second UI)** · [Code sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Why a second UI?

[LibreChat](https://www.librechat.ai/) is a second chat interface that runs **alongside** Open WebUI — on the same LiteLLM, with the same models and the same tools. You don't have to choose: both are reachable at once, each with its own login and its own chat history.

The practical difference is in the tools:

| | Open WebUI | LibreChat |
|---|---|---|
| Models | via LiteLLM | via LiteLLM (the same ones) |
| MCP tools | only via **mcpo** (MCP → OpenAPI) | **directly**, MCP native |
| Enabling tools | per model, [five settings](tools.md#checklist-enabling-tools-per-model) | per conversation, in the chat |
| Tool names in chat | renamed (`tool_run_script_post`) | original name (`run_script`) |

Open WebUI does **not** understand raw MCP, only OpenAPI — which is why `mcpo` sits in between as a translator (details: [Tools for the LLM](tools.md#enable-the-tools-in-open-webui-mcpo)). That extra hop costs stability:

- `mcpo` holds open sessions to `mcp`, `sandbox-mcp` and `android-mcp`. If one of those restarts without `mcpo` restarting too, the tools return `MCP session is not available` — that's what [`scripts/restart-mcp.sh`](operations.md) is for.
- `mcpo` renames tools. The model sees `tool_run_script_post`, not `run_script` — so a prompt that names a tool explicitly goes nowhere.

**LibreChat speaks MCP natively.** Both problems disappear: no translation layer, no renamed tools, no torn-down sessions. That's exactly why it's included here — as something to compare against when tool calls misbehave in Open WebUI.

What else LibreChat brings: **agents** (multi-step flows with tools assigned up front), **branching** conversations, and answers from several models side by side in one conversation.

## Getting started

LibreChat starts along with the rest of the stack — `install.sh` creates every key it needs in `.env`, so there is no extra step.

```bash
docker compose -f docker-compose.rocm.yml up -d librechat librechat-mongo
docker logs -f librechat        # the first start takes a moment
```

Then open it in the browser:

```
http://<server-ip>:3080
```

(Also available as the "LibreChat" dashboard tile.)

**The installer creates the credentials for you** — no need to register first. To see them:

```bash
./scripts/show-credentials.sh          # LibreChat section
./scripts/librechat-user.sh --show     # LibreChat only
```

The [control center](control-center.md) shows the same under **LibreChat → Zugangsdaten anzeigen**.

| | |
|---|---|
| Email | `admin@stack.local` (change via `LIBRECHAT_ADMIN_EMAIL`) |
| Password | generated once at random, stored in `.env` |

The password is deliberately **not** hard-coded: LibreChat can reach your vault through the MCP tools, so a well-known default password would be the worst idea in the whole stack. Change it in LibreChat after your first sign-in.

Registration is therefore **closed** from the start (`LIBRECHAT_ALLOW_REGISTRATION=false`). If you want other people to sign themselves up:

```bash
sed -i 's/^LIBRECHAT_ALLOW_REGISTRATION=.*/LIBRECHAT_ALLOW_REGISTRATION=true/' .env
docker compose -f docker-compose.rocm.yml up -d librechat
```

Creating another account by hand (LibreChat's own command):

```bash
docker exec -it librechat npm run create-user
docker exec librechat npm run list-users
```

If the first account wasn't created during install — because LibreChat wasn't ready yet, say — do it afterwards:

```bash
./scripts/librechat-user.sh
```

## Setting your own user and password

The generated defaults are just a starting point. For your own:

```bash
./scripts/set-credentials.sh librechat
```

(In the [control center](control-center.md): **LibreChat → Eigenen Benutzer und Passwort festlegen**.)

The script asks for email and password — the password without echo and twice, to catch typos. If the account exists, the password is changed (via LibreChat's `reset-password`, which invalidates all existing sessions); if not, the account is created.

When creating an account, the *username* — a separate thing from the email in LibreChat — is derived from the part before the `@`, with a digit appended if it is already taken. LibreChat requires unique usernames; passing a fixed `admin` would make every second account fail. The chosen name is printed and recorded as `LIBRECHAT_ADMIN_USERNAME` in `.env`.

**A password you choose yourself is not stored.** All `.env` keeps afterwards is the username and a note of when you set your own:

```
LIBRECHAT_ADMIN_EMAIL=me@example.com
LIBRECHAT_ADMIN_PASSWORD=
LIBRECHAT_ADMIN_PASSWORD_SET=2026-08-18T08:00
```

The credentials display then says exactly that:

```
  E-Mail:      me@example.com
  Passwort:    (selbst gesetzt am 2026-08-18T08:00, nicht gespeichert)
```

You know it already — keeping a second copy in plain text on disk would only add risk. **Write it down**: it can't be displayed again afterwards.

Back to a generated password (which is shown again):

```bash
./scripts/set-credentials.sh librechat --reset
```

The same works for **Syncthing** (UI user and password). For **Open WebUI** you can only set what a *new* account will be created with — an existing one you change in its own UI (Profile → Settings → Account). LiteLLM has no separate password: the master key *is* the login.

## Using tools in the chat

Unlike Open WebUI, there is **no per-model configuration**. The MCP services are already declared in `librechat/librechat.yaml`; you pick them per conversation:

1. New conversation, pick a model (endpoint **"LiteLLM"**)
2. Click the tool icon in the input area
3. Enable the servers you want — `mcp_gateway`, `code_sandbox`, `android_build`

Then just ask normally: *"Look in my knowledge base and tell me what's under 01inbox"* or *"Write a bash script that … — run it and show me the real output."*

> **Still don't name tools in the prompt.** Even though LibreChat passes the original names through: describe the task ("run it and show the real output") rather than the tool. The model then picks for itself — whereas given a name it can't find, it picks nothing at all.

The three servers are the same ones Open WebUI uses:

| Server | What it does | Docs |
|---|---|---|
| `mcp_gateway` | Filesystem (`/vault`, `/workspace`), web fetch, timezones, GitHub, search, DB | [Tools for the LLM](tools.md) |
| `code_sandbox` | Run and test code (Python, shell, Java, Go, C++, optionally PowerShell) | [Code sandbox](code-sandbox.md) |
| `android_build` | Create, build and test Android projects | [Android development](android.md) |

The descriptions the model sees for each server (`serverInstructions` in the YAML) also tell it what is **not** there — no network in the sandbox, `/work` persists, `/tmp` doesn't. That saves you the endless guessing loops that happen when a model doesn't know the limits of its own tools.

## Model icons and names

In Open WebUI you click a model and change its picture and name in the edit dialog. LibreChat has no such dialog — here it lives in [`librechat/librechat.yaml`](../../librechat/librechat.yaml). In exchange, it's the same for every user.

Two levels:

**The whole endpoint** — one icon for every model under it:

```yaml
endpoints:
  custom:
    - name: "LiteLLM"
      iconURL: "/images/litellm.png"
      modelDisplayLabel: "LiteLLM (lokal)"
```

**Individual models** — via `modelSpecs`. Each entry is a profile with its own name, icon and description; `preset` says which model is actually behind it:

```yaml
modelSpecs:
  enforce: false      # the normal model list stays selectable too
  prioritize: true    # profiles appear at the top of the picker
  list:
    - name: "gemma-lokal"
      label: "Gemma 3 12B"
      description: "All-rounder, runs on your own GPU"
      iconURL: "/images/gemma.png"
      showIconInMenu: true
      showIconInHeader: true
      order: 1
      preset:
        endpoint: "LiteLLM"
        model: "ollama/gemma3:12b"
```

A commented-out example is already in the file — uncomment, adjust, restart.

### Where the images go

`iconURL` takes three kinds of value:

| Value | Meaning |
|---|---|
| `/images/custom/gemma.png` | Your own file from the `images/` folder |
| `https://…/logo.png` | Any address on the web |
| `openAI`, `google`, `anthropic`, … | Reuse one of the built-in icons |

Your own images belong in the **`images/`** folder in the project directory. It's mounted read-only into the container, and LibreChat serves everything in it under `/images/custom/`:

```bash
cp my-logo.png ~/self-hosted-llm-stack/images/
# then in the YAML:  iconURL: "/images/custom/my-logo.png"
```

No `docker cp` needed, and the images survive recreating the container. A **new image** is available immediately (reload the page); only a change to the YAML needs a restart.

Square PNG or SVG from about 128×128 looks best.

> Every change to the YAML needs a restart of `librechat` — the file is only read at startup.

## Where MCP is configured — and what to do when tools are missing

There's no MCP settings dialog in LibreChat: the servers live in [`librechat/librechat.yaml`](../../librechat/librechat.yaml) under `mcpServers`. What you pick in the UI is only *which* of the connected tools a conversation or an agent may use.

**Important:** LibreChat connects its MCP servers **at startup**. If a service wasn't running then — or was recreated since, e.g. by `restart-mcp.sh` — it stays invisible to LibreChat until LibreChat itself restarts:

```bash
docker compose -f docker-compose.rocm.yml restart librechat
```

### Error: `AGENT_EXPECTED_MCP_TOOLS_UNAVAILABLE`

An **agent** has MCP tools assigned, but LibreChat couldn't connect any MCP server. The diagnosis walks the whole chain:

```bash
./scripts/diagnose-mcp.sh
```

(Also in the [control center](control-center.md), on every MCP service under **Werkzeuge prüfen**.)

It checks: are the services running, is `MCP_API_KEY` set **and did it reach the container**, do the services answer a real MCP `initialize` request from inside the LibreChat container, what does the log say, and is the `mcpServers` block in the config at all.

The most common causes:

| Cause | How it shows in the log | Fix |
|---|---|---|
| **SSRF protection blocks internal addresses** | `Domain "http://mcp:3000" is not allowed` | `mcpSettings.allowedAddresses` (included since `git pull`), then `restart librechat` |
| LibreChat started before the MCP services | `Failed to initialize` / `ECONNREFUSED` | `docker compose -f docker-compose.rocm.yml restart librechat` |
| `MCP_API_KEY` missing or empty in the container | HTTP 401 during the probe | `./scripts/wire-mcp.sh`, then `up -d --force-recreate librechat` |
| **LibreChat wrongly thinks the server needs OAuth** | `OAuth Required: true`, `Capabilities: undefined` | `requiresOAuth: false` in `librechat.yaml` (see below) |
| The agent has no tools selected | only `[ResumableAgentController]`, nothing else | Agents → Edit → Tools |

### "N tools" doesn't mean every server delivered

`Initialized with 3 configured servers and 8 tools` sounds fine, but says nothing about **which** server contributed. 8 can just as well be 5 + 3 + **0**. So the diagnosis counts per server:

```
5/6 · Werkzeuge je Server
  ✓ code_sandbox: 3 Werkzeuge
  ✓ android_build: 5 Werkzeuge
  ✗ mcp_gateway liefert KEINE Werkzeuge
```

If `mcp_gateway` of all things delivers nothing, two causes are possible — the diagnosis (`./scripts/diagnose-mcp.sh`) tells them apart in step 5b by querying the gateway directly, bypassing LibreChat:

**MCPHub has no active servers.** Then the direct query itself reports 0 tools:

```bash
./scripts/wire-mcp.sh
docker exec mcp cat /var/lib/mcp/mcp_settings.json
```

That hits exactly the tools you're most likely to miss: filesystem (vault), web fetch and timezones.

**LibreChat wrongly thinks the server needs OAuth.** Then the direct query returns the tools just fine — only LibreChat itself doesn't see them. The log shows this on connect:

```
[MCP][mcp_gateway] OAuth Required: true
[MCP][mcp_gateway] Capabilities: undefined
[MCP][mcp_gateway] Tools: undefined
```

LibreChat checks at startup whether a server needs OAuth — and it does so **without** the configured `Authorization` header, since the whole point is to find out whether one is needed. Caddy sits in front of MCPHub as a reverse proxy and secures **every** path under port 3000 with the bearer key, including the `.well-known` OAuth-discovery paths. The unauthenticated probe gets a `401` there instead of a clean `404` — and LibreChat reads that as "needs OAuth", even though the same bearer key works fine for actual tool calls. (Whether MCPHub's own OAuth server is on or off makes no difference here — `wire-mcp.sh` turns it off anyway, since this stack doesn't need it.)

Fix: `librechat/librechat.yaml` now sets `requiresOAuth: false` on `mcp_gateway` (present since your last `git pull`) — the documented field that skips exactly this auto-detection per server. Then just:

```bash
docker compose -f docker-compose.rocm.yml restart librechat
```

On MCP restarts in general: LibreChat only queries its MCP servers at its own startup and never checks again. **Any** restart of `mcp` — for whatever reason — invalidates LibreChat's cached state until LibreChat itself restarts. `./scripts/wire-mcp.sh` triggers that restart automatically whenever it restarts `mcp`; after a manual `docker restart mcp`, that's on you.

### Why SSRF protection kicks in

With **no** allowlist configured, LibreChat pre-emptively blocks any target resolving to a **private IP** — standard protection against SSRF (tricking the server into probing internal addresses). Docker-internal names like `mcp` or `sandbox-mcp` resolve to exactly that, `172.x`. So your own services fall under that protection.

The fix lives in `librechat/librechat.yaml`:

```yaml
mcpSettings:
  allowedAddresses:
    - "mcp:3000"
    - "sandbox-mcp:8000"
    - "android-mcp:8000"
```

`allowedAddresses` is the mechanism made for this: it only applies to private IP space and requires `host:port`, so the exemption is scoped to one service port rather than the whole host.

> Deliberately `allowedAddresses` and **not** `allowedDomains`: setting an `allowedDomains` list disables SSRF protection entirely. This way it stays on and exactly these three ports are exempt. A new MCP service has to be added here too.

> That last one explains why it "works without MCP": with no tools assigned the model simply answers from its own knowledge.

### Web search

The MCP Gateway's tools include **fetch**, not search: fetch retrieves a page whose address is already known. A question like "search the web for …" can't be answered with it — there's no search engine behind it.

Two routes: LibreChat's own web search (`webSearch` in the YAML, needs an account with a search provider) or your own MCP search server declared under `mcpServers`. Neither is set up in this stack yet.

## Adjusting the configuration

Everything substantive lives in [`librechat/librechat.yaml`](../../librechat/librechat.yaml) — endpoints, MCP servers, UI options. After every change:

```bash
docker compose -f docker-compose.rocm.yml restart librechat
```

The model list is fetched from LiteLLM at runtime (`fetch: true`). A new model you register with LiteLLM ([Managing models](models.md)) shows up in LibreChat automatically — the YAML doesn't need touching.

`.env` switches:

| Variable | Default | Meaning |
|---|---|---|
| `PORT_LIBRECHAT` | `3080` | UI port |
| `LIBRECHAT_ALLOW_REGISTRATION` | `false` | Registration closed; the installer creates the first account |
| `LIBRECHAT_ADMIN_EMAIL` | `admin@stack.local` | Login of the first account |
| `LIBRECHAT_ADMIN_PASSWORD` | generated | Password of the first account |
| `LIBRECHAT_CREDS_KEY` / `_IV` | generated | Encryption of stored credentials (64 and 32 hex characters) |
| `LIBRECHAT_JWT_SECRET` / `_REFRESH_SECRET` | generated | Session tokens |

> `install.sh` generates those four keys once. **Don't change them afterwards** — stored credentials become unreadable and every session is invalidated. If you do have to rotate them, all users have to sign in again.

## Removing LibreChat again

None of this is mandatory — Open WebUI keeps running independently.

```bash
docker compose -f docker-compose.rocm.yml stop librechat librechat-mongo
```

Permanently: comment out both services in `docker-compose.rocm.yml`. The data lives in the volumes `librechat-mongo`, `librechat-data` and `librechat-uploads` and stays until you delete it:

```bash
docker volume rm librechat-mongo librechat-data librechat-uploads   # deletes accounts and history
```

## When it doesn't work

```bash
docker logs librechat --tail 50
docker logs librechat-mongo --tail 20
```

| Symptom | Cause |
|---|---|
| Container won't start, message about `CREDS_KEY` | Key missing or wrong length — 64 hex characters for `CREDS_KEY`, 32 for `CREDS_IV`. Regenerate: `openssl rand -hex 32` and `-hex 16` |
| No models in the picker | Is LiteLLM reachable? `docker exec librechat curl -s http://litellm:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"` |
| Tools missing in the chat | `docker logs librechat \| grep -i mcp` — it reports at startup which MCP servers were connected |
| `mcp_gateway` won't connect | Is `MCP_API_KEY` set in `.env`? If not, run `./scripts/wire-mcp.sh` |
| Can't sign in, registration disabled | That's intended — sign in with the credentials from `show-credentials.sh`, or set `LIBRECHAT_ALLOW_REGISTRATION=true` for self-registration |
| Credentials don't work | Was the account created? `docker exec librechat npm run list-users`. Create it: `./scripts/librechat-user.sh` |

## Security

The same rule applies as for Open WebUI and the dashboard: **don't put it on the internet unprotected.** In `lan` mode, `install.sh` opens port `3080` for the local network only. For outside access, put a reverse proxy with login and MFA in front — see [Security & remote access](security.md).

Through `code_sandbox` and `android_build` the chat can execute code, and through `mcp_gateway` it has **write access to the vault**. An open login is therefore equivalent to access to your knowledge base.
