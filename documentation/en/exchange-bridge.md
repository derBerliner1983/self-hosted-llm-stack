# Exchange Bridge

A folder you and the LLM both see at once — upload/download on either side.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/austausch-ablage.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · [Excalidraw](excalidraw.md) · **Exchange Bridge** · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## What for

An agent builds you an Android app, writes a script, produces a file — and then? Without somewhere to put it, all you get is copying source code out of the chat. That doesn't even work for a built APK.

The exchange bridge is a plain folder that two sides see at once:

- **You, in the browser** — upload, download, browse, delete.
- **The LLM, via the filesystem tool** (`mcp_gateway`, the same one used for the [vault](knowledge-base.md)) — read and write.

Deliberately **not** the vault itself — that stays the knowledge base, not a dumping ground for build output or test scripts.

## Address and credentials

```
http://<server-ip>:8900
```

`install.sh` generates credentials automatically — unlike the read-only [dashboard](control-center.md), this one can also write, hence the password:

```bash
./scripts/service-credentials.sh exchange-bridge
```

In the [control center](control-center.md): **Austausch-Ablage → Zugangsdaten anzeigen**.

Set your own username/password:

```bash
./scripts/set-credentials.sh exchange-bridge
```

(Your own password is, as with every other service that offers this, **not** stored in `.env`. See the [LibreChat docs](librechat.md#setting-your-own-user-and-password), which introduce the same mechanism.)

## Using it from the chat

Just tell the model what to do — it sees `/exchange` automatically through the filesystem tool once you enable it, in LibreChat (`mcp_gateway`) or Open WebUI:

> Copy the finished APK to /exchange so I can download it.

> Read /exchange/testdata.csv and analyze it.

For the Android agent this is now built in: `gradle` (the `create_project`/`gradle` tools in [android-mcp](android.md)) knows where a built APK lands, and that it needs moving to `/exchange` for download.

## How it works

```
Browser  <--HTTP, Basic Auth-->  exchange-bridge  <--same volume-->  mcp (filesystem tool)
```

`exchange-bridge` is a small, dependency-free Python service (no framework, same style as the [dashboard](control-center.md) and vault-bridge) — list, upload, download, delete, secured with Basic Auth. The same Docker volume is mounted read-write into the `mcp` container, listed in `MCP_FILESYSTEM_DIRS` — the filesystem tool sees the folder directly, same as `/vault` and `/workspace`.

## Limits

- **No framework, no virus scanning, no preview** — whatever you upload lands in the folder unchanged. The same caution applies here as anywhere else for files you don't trust.
- **A per-file upload limit** exists (`EXCHANGE_MAX_UPLOAD_MB`, default 500 MB) — no limit on the folder as a whole. Keep disk space in mind.
- **No directory tree** — the folder is deliberately flat, no subfolders. For more structure, the [vault](knowledge-base.md) or [Syncthing](knowledge-base.md#syncthing-alternative-to-vault-bridge) remain the right tool.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `PORT_EXCHANGE_BRIDGE` | `8900` | Host port |
| `EXCHANGE_USER` | `admin` | Username (Basic Auth) |
| `EXCHANGE_PASSWORD` | generated | Password — empty once a custom one is set |
| `EXCHANGE_MAX_UPLOAD_MB` | `500` | Per-file limit |
| `URL_EXCHANGE_BRIDGE` | empty | Custom address (reverse proxy) instead of IP:port |

## Removing it

```bash
docker compose -f docker-compose.rocm.yml rm -sf exchange-bridge
docker volume rm exchange-data   # deletes uploaded files permanently
```

Without the second command, uploaded files stay around in case you need the service again later.
