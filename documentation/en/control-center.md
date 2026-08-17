# Control center (menu)

One menu for everything: see what's already there, add what isn't, start it, remove it.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/kontrollzentrum.md)

**Documentation:** [Installation & getting started](installation.md) · **Control center (menu)** · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Opening it

```bash
./stack-menu.sh          # or equivalently:
./install.sh --menu
```

The header with the logo and summary **stays put at the top** — even while a command is running. Output scrolls only in the area below it.

```
        ┌─┬─┬─┬─┐
    ┌───┴─┴─┴─┴───┐
    │  ▄▄     ▄▄  │      SELF-HOSTED
  ──┤  ██  ▄  ██  ├──    A I   S T A C K
    │  ▀▀  █  ▀▀  │
    └───┬─┬─┬─┬───┘
        └─┴─┴─┴─┘
  docker-compose.rocm.yml  ● Docker  Dienste: 12 läuft · 2 fehlt · 14 gesamt
  ────────────────────────────────────────────────────────────────────────
  Chat-Oberflächen
  ❯ Open WebUI             ● läuft       Chat-Oberfläche (Werkzeuge über mcpo)
    LibreChat              ◍ gestoppt    Zweite Oberfläche, MCP nativ
```

> The menu itself is in German, like the installer and the other scripts in this repository.

## What you're looking at

Each row shows **what state that building block is in right now** — what would otherwise take several `docker ps` calls:

| Display | Meaning |
|---|---|
| ● läuft / bereit / installiert | Present and active |
| ▲ teilweise | Only part of a multi-container service is up (e.g. LibreChat without its database) |
| ▲ ungesund | Container is running but reports a failing healthcheck |
| ◍ gestoppt / aus | Created, but not currently running |
| ○ nicht da / fehlt / offen | Not installed yet |

The header line summarises: compose file, Docker state, how many services are running and how many are missing.

## Keys

| Key | Effect |
|---|---|
| `↑` `↓` or `k` `j` | Select an entry |
| `Enter` | Open the actions for that entry |
| `s` | Start service (on service entries) |
| `x` | Stop service |
| `l` | Show logs (last 200 lines) |
| `r` | Re-read state |
| `q` | Quit |
| `Esc` | Back out of a submenu |

## The sections

**Einrichtung (setup)** — run `install.sh`, check only (`--check-only`, changes nothing), show credentials.

**Kern · Chat-Oberflächen · Werkzeuge · Wissensdatenbank · Zusatzdienste** — every service from the compose file. Per service: start, restart, stop, logs, rebuild, remove container (data volumes are kept).

**CLI-Werkzeuge** — [Open Interpreter](open-interpreter.md). Not a service but a command-line tool: here you see whether it's built, and start it.

**System** — Docker, Docker Compose, GPU/ROCm, firewall and `.env`. Each can be inspected and, where it makes sense, changed: view firewall rules, open ports for the LAN only, edit `.env`.

**Aufräumen und entfernen (cleanup and removal)** — from harmless to final:

| Entry | What happens |
|---|---|
| Alles stoppen | Containers stop, nothing is lost |
| Alles neu starten | `up -d` across the whole stack |
| MCP-Dienste neu starten | `restart-mcp.sh` — in the right order, see [Operations](operations.md) |
| Ungenutztes aufräumen | Dangling images and build cache |
| Stack entfernen | Containers gone, **data volumes kept** |
| Stack + alle Daten löschen | Models, chats, database, `.env` — **final** |
| Docker deinstallieren | Docker packages off the system, optionally `/var/lib/docker` |

> The last two don't ask yes/no — they require a typed word (`loeschen` and `docker weg` respectively). A stray Enter deletes nothing. **Uninstalling Docker affects every container on the machine**, not just this stack.

## When something doesn't work

Every command's output is also written to a log file; the path is shown at the bottom of the screen after the run. It's cleaned up on exit, so copy it first if you need it.

| Symptom | Cause |
|---|---|
| "stack-menu.sh braucht ein interaktives Terminal" | Started through a pipe or from a script — the menu needs a real terminal |
| Everything says "nicht da" although it's running | Docker daemon unreachable, or your user isn't in the `docker` group |
| Box characters and umlauts are mangled | No UTF-8 locale — the menu falls back to plain ASCII; for the nicer rendering set `LANG=en_US.UTF-8` (or `C.UTF-8`) |
| Menu leaves artefacts behind | Terminal too small; roughly 50×12 characters is the usable minimum |

Using a different compose file:

```bash
COMPOSE_FILE=docker-compose.yml ./stack-menu.sh
NO_COLOR=1 ./stack-menu.sh          # no colours
```
