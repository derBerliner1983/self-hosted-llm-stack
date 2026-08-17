# Knowledge base (Obsidian vault)

Connecting your own vault as knowledge for the LLM — via Syncthing or Vault-Bridge.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/wissensdatenbank.md)

**Documentation:** [Installation & getting started](installation.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Android development](android.md) · **Knowledge base (vault)** · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Syncthing (alternative to Vault-Bridge)

If your vault is already synced by a **dedicated Nextcloud client** running on another device (e.g. the official Windows desktop client), that client and Vault-Bridge can get in each other's way — two independent two-way sync engines operating on the same files lead to locks, conflicts, and aborted sync runs. [Syncthing](https://syncthing.net/) sidesteps this by syncing **directly** between your devices, with no Nextcloud detour at all — and it handles conflicts safely: for a file changed on both sides, it **never** silently overwrites, but instead creates a second file named `.sync-conflict-<timestamp>-<device>`.

**Setup:**

1. Start/update the stack (`docker compose -f docker-compose.rocm.yml up -d syncthing`) — the web UI runs at `http://<server-ip>:8384` (or via the "Syncthing" tile on the dashboard).
2. **Set a password immediately:** Settings → GUI → Authentication — the UI ships with **no** password by default.
3. Install the [Syncthing client](https://syncthing.net/downloads/) on your other device (Windows/Mac/Linux) and open its web UI too.
4. On both sides, copy the device ID under "This Device" and add it on the other device as a "Remote Device".
5. On the server, share a new folder pointing at `/var/syncthing/vault` (the same `vault-data` volume the MCP Gateway filesystem tool also sees) — accept it on the other device and pick the local target folder there (e.g. your existing Obsidian vault folder).

> ⚠️ Use **only one** of the two (Vault-Bridge **or** Syncthing) for the same folder — never both at once, for the same reason a Nextcloud client + Vault-Bridge got in each other's way. If you switch to Syncthing: click "Disconnect" in the Vault-Bridge UI so it stops touching the same folder.

Configurable via `.env`: `PORT_SYNCTHING_GUI` (default `8384`). The sync/discovery ports (22000 tcp+udp, 21027/udp) are fixed and are opened by `install.sh` for the LAN only regardless of firewall mode (no reason to expose them publicly).

## Vault-Bridge (Obsidian/Nextcloud as knowledge for the LLM)

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
