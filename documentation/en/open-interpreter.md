# Open Interpreter (CLI)

A command-line assistant: describe a task, the model writes code and runs it.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/open-interpreter.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · **Open Interpreter (CLI)** · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## What it is — and what it isn't

[Open Interpreter](https://github.com/OpenInterpreter/open-interpreter) is an assistant for the **command line**, not a web UI. You describe a task, the model writes code (Python, shell, JavaScript, …), runs it, sees the result and keeps going until the task is done.

How it differs from the [code sandbox](code-sandbox.md): the sandbox is a **tool for the chat model** — you talk to Open WebUI or LibreChat, and the model reaches for the sandbox along the way. Open Interpreter is the other way round: it *is* the program you're using, in the terminal, with no chat UI in between.

It uses the same LiteLLM as everything else — so your local model, no cloud.

## Installing

The installer asks:

```
Open Interpreter — Kommandozeilen-Assistent: du beschreibst eine
Aufgabe, das Modell schreibt Code und führt ihn aus. Läuft im Container
(sieht nur den Arbeitsbereich /work) und nutzt dein lokales LiteLLM.
Kein Dienst — wird nur auf Zuruf gestartet: ./scripts/interpreter.sh

Open Interpreter mitinstallieren? [j/N]
```

Your answer is stored as `INSTALL_OPEN_INTERPRETER` in `.env`; the next run won't ask again. Without the prompt:

```bash
./install.sh --with-interpreter      # include it
./install.sh --without-interpreter   # skip it
```

To add it later — in the [control center](control-center.md) under **CLI-Werkzeuge → Open Interpreter → Installieren**, or directly:

```bash
./scripts/interpreter.sh --build
```

## Running it

```bash
./scripts/interpreter.sh                          # interactive session
./scripts/interpreter.sh --model ollama/qwen2.5:14b
./scripts/interpreter.sh -y                       # don't ask before each step
```

Any further arguments are passed straight through to Open Interpreter.

The first start builds the image (a few minutes). If LiteLLM isn't running, the script starts it — otherwise Open Interpreter would only fail at the first prompt with a connection message nobody can place.

## Why it runs in a container

Open Interpreter executes whatever the model writes. On the host that would mean access to everything your user can reach — including your knowledge base and your configuration.

So here it runs **in a container** and sees only `/work`:

- The `/work` workspace is the same volume (`sandbox-work`) the [code sandbox](code-sandbox.md) uses. Whatever the chat model created there, you'll find here — and vice versa.
- Everything else on your machine simply doesn't exist as far as Open Interpreter is concerned. The vault in particular does **not**.
- A `docker rmi` removes it without a trace, instead of leaving hundreds of Python packages on the system.

If you need more access, mount it deliberately — on the `interpreter` service in `docker-compose.rocm.yml`:

```yaml
    volumes:
      - sandbox-work:/work
      - ${VAULT_HOST_PATH:-./vault}:/vault:ro   # vault READ-ONLY
```

> Mount the vault, if at all, **only with `:ro`**. Write access for a tool that runs code on its own initiative is exactly how a knowledge base quietly fills up with junk.

## Settings

All via `.env`:

| Variable | Default | Meaning |
|---|---|---|
| `INSTALL_OPEN_INTERPRETER` | prompt | `yes` / `no` — remembers your choice |
| `INTERPRETER_MODEL` | `ollama/gemma3:12b` | Model name **as registered with LiteLLM** |
| `INTERPRETER_CONTEXT_WINDOW` | `16384` | Context window |
| `INTERPRETER_MAX_TOKENS` | `4096` | Maximum response length |
| `INTERPRETER_API_BASE` | `http://litellm:4000/v1` | Endpoint |
| `OPEN_INTERPRETER_VERSION` | `0.4.3` | Package version in the image |

To see which model names you have:

```bash
docker exec litellm curl -s http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | grep -o '"id":"[^"]*"'
```

> **About the prefix:** LiteLLM knows the models as `ollama/<name>`. Open Interpreter uses the litellm library internally, and that needs a leading `openai/` so it treats the LiteLLM proxy as an OpenAI-compatible endpoint instead of trying to reach Ollama itself. So `ollama/gemma3:12b` becomes `openai/ollama/gemma3:12b` — **the container adds that itself**; put the short name in `.env`.

## Limits

- **The network is not restricted** — the container sits on the stack's Docker network and can therefore reach the internet too. If you don't want that, set `network_mode: none` on the service; but then LiteLLM is out of reach as well.
- **Small models fail here more often** than in chat: Open Interpreter demands clean, multi-step tool behaviour. If it loops, a bigger model helps more than a better prompt.
- **`-y` really does mean no confirmation.** Inside the container the blast radius is `/work` — which is exactly why it's offered here.

## If it fails to start

**`ModuleNotFoundError: No module named 'pkg_resources'`**

An image built too early. Open Interpreter imports `pkg_resources`, which lives in `setuptools` — and Python has not shipped that by default since 3.12. The Dockerfile now installs it explicitly; the image just needs rebuilding:

```bash
git pull
docker compose -f docker-compose.rocm.yml --profile cli build interpreter
```

In the [control center](control-center.md): **Open Interpreter → Image neu bauen**. No `--no-cache` needed: the changed Dockerfile line invalidates everything from there on by itself.

The build now checks that Open Interpreter can actually be imported. If that fails, no image is produced at all — better than finding out the moment you want to use the thing.

## Removing it

In the [control center](control-center.md): **Open Interpreter → Entfernen**. Or:

```bash
docker compose -f docker-compose.rocm.yml --profile cli down --rmi local interpreter
```

`/work` survives — that volume belongs to the code sandbox too.
