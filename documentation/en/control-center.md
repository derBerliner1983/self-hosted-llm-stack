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
| `o` | Show the service's address |
| `r` | Re-read state |
| `q` | Quit |
| `Esc` | Back out of a submenu |

## Service addresses

Open a service with `Enter` and its address is right there in the heading; the `o` shortcut shows it full size:

```
  LibreChat  http://192.168.1.50:3080/

   ❯ Neu starten
     Adresse anzeigen (zum Anklicken)
     Adresse festlegen (eigene Domain / anderer Host)
```

The address is built from the port (`.env`) and the IP of the machine the menu runs on. In terminals that support hyperlinks — Windows Terminal, iTerm2, GNOME Terminal, WezTerm, Kitty — it is **clickable** and opens the browser. PuTTY can't do that; there the address is plain text to select and copy. Turn it off with `MENU_HYPERLINKS=0 ./stack-menu.sh`.

**Storing your own address** — the name behind a reverse proxy, for instance: pick **Adresse festlegen**, type it, done. It's written to `.env` as `URL_<SERVICE>` and takes precedence from then on. Without a scheme, `http://` is prepended. Leaving it empty removes it again.

| Service | Variable |
|---|---|
| Open WebUI | `URL_OPEN_WEBUI` |
| LibreChat | `URL_LIBRECHAT` |
| LiteLLM | `URL_LITELLM` |
| Dashboard | `URL_DASHBOARD` |
| Vault-Bridge | `URL_VAULT_BRIDGE` |
| Syncthing | `URL_SYNCTHING` |
| mcpo | `URL_MCPO` |
| MCP Gateway | `URL_MCP` |

`./scripts/show-credentials.sh` uses the same values. If the menu picks the wrong IP (several network interfaces), set `STACK_HOST` in `.env`.

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
| Lines stagger diagonally to the right | Fixed — happened before `94e3c83`, when the terminal was switched to raw mode and `\n` lost its carriage return. A `git pull` is enough |

Using a different compose file:

```bash
COMPOSE_FILE=docker-compose.yml ./stack-menu.sh
NO_COLOR=1 ./stack-menu.sh          # no colours
```
