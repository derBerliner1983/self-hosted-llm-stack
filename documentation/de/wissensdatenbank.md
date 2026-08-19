# Wissensdatenbank (Obsidian-Vault)

Den eigenen Vault als Wissen fürs LLM anbinden — per Syncthing oder Vault-Bridge.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/knowledge-base.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Austausch-Ablage](austausch-ablage.md) · **Wissensdatenbank (Vault)** · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Syncthing (Alternative zur Vault-Bridge)

Läuft dein Vault schon über einen **eigenen Nextcloud-Client** auf einem anderen Gerät (z. B. dem offiziellen Windows-Desktop-Client), können sich der und die Vault-Bridge gegenseitig in die Quere kommen — zwei unabhängige Zwei-Wege-Sync-Systeme auf denselben Dateien führen zu Sperren, Konflikten und abgebrochenen Sync-Läufen. [Syncthing](https://syncthing.net/) löst das, indem es **direkt** zwischen deinen Geräten synct, ganz ohne Nextcloud als Umweg — und behandelt Konflikte sicher: Bei einer Datei, die auf beiden Seiten geändert wurde, wird **nie** stillschweigend überschrieben, sondern eine zweite Datei mit `.sync-conflict-<Zeitstempel>-<Gerät>` im Namen angelegt.

**Einrichten:**

1. Stack starten/aktualisieren (`docker compose -f docker-compose.rocm.yml up -d syncthing`) — die Web-Oberfläche läuft unter `http://<server-ip>:8384` (oder über die Dashboard-Kachel „Syncthing").
2. **Sofort ein Passwort setzen:** Einstellungen → GUI → Authentifizierung — die Oberfläche hat standardmäßig **kein** Passwort.
3. [Syncthing-Client](https://syncthing.net/downloads/) auf deinem anderen Gerät (Windows/Mac/Linux) installieren, dort ebenfalls die Web-Oberfläche öffnen.
4. Auf beiden Seiten unter „Diese Gerät" die Geräte-ID kopieren und beim jeweils anderen Gerät als „Remote-Gerät hinzufügen" eintragen.
5. Auf dem Server einen neuen Ordner freigeben, der auf `/var/syncthing/vault` zeigt (dasselbe `vault-data`-Volume, das auch das MCP-Gateway-Dateisystem-Werkzeug sieht) — beim anderen Gerät annehmen und dabei den lokalen Zielordner auswählen (z. B. deinen bestehenden Obsidian-Vault-Ordner).

> ⚠️ Nutze **immer nur eins** von beiden (Vault-Bridge **oder** Syncthing) für denselben Ordner — niemals gleichzeitig, aus demselben Grund, aus dem Nextcloud-Client + Vault-Bridge sich in die Quere kamen. Falls du auf Syncthing wechselst: in der Vault-Bridge-Oberfläche „Trennen" klicken, damit sie aufhört, denselben Ordner anzufassen.

Konfigurierbar über `.env`: `PORT_SYNCTHING_GUI` (Standard `8384`). Die Sync-/Erkennungs-Ports (22000 tcp+udp, 21027/udp) sind fest und werden von `install.sh` unabhängig vom Firewall-Modus nur fürs LAN geöffnet (kein Grund, sie öffentlich zu exponieren).

## Vault-Bridge (Obsidian/Nextcloud als Wissen fürs LLM)

Du kannst einen auf **Nextcloud** gehosteten **Obsidian-Vault** an den Stack anbinden — nicht als „KI in Obsidian einbauen", sondern umgekehrt: **alle** an LiteLLM angebundenen Clients (Open WebUI, künftig z. B. Claude) bekommen über das MCP-Gateway-Dateisystem-Werkzeug lesenden Zugriff auf dein eigenes Wissen. Dafür bringt der Stack den `vault-bridge`-Dienst mit — eine eigene, **web-konfigurierbare** Brücke, kein Handbetrieb über die `.env`.

**Einrichten:**

1. In Nextcloud ein **App-Passwort** erzeugen (Profil → Sicherheit → „Neues App-Passwort erzeugen") — nicht das Hauptpasswort verwenden.
2. Vault-Bridge-Oberfläche öffnen: `http://<server-ip>:8700` (oder über die Dashboard-Kachel „Vault-Bridge")
3. Server-URL, Benutzername, App-Passwort und ein Sync-Intervall eintragen. Für den Vault-Pfad entweder direkt eintippen (z. B. `Notizen/ObsidianVault`) oder über **„Ordner durchsuchen…"** durch die eigene Nextcloud-Ordnerstruktur klicken, statt sich zu vertippen. Dann **„Verbinden & synchronisieren"**.

Sobald der erste Sync erfolgreich war, sieht das **MCP-Gateway-Dateisystem-Werkzeug den Vault automatisch** — Bridge und MCP Gateway teilen sich dasselbe Docker-Volume (`vault-data`), ein Neustart von `mcp` ist nicht nötig. Auch in Open WebUI ist kein zusätzlicher Eintrag nötig: Es ist derselbe `mcp_gateway`-Werkzeug-Server, den du ohnehin schon eingebunden hast (siehe oben, „Werkzeuge in Open WebUI aktivieren").

**Wie es technisch funktioniert:** `vault-bridge` nutzt [`rclone`](https://rclone.org/) im **Sync-**, nicht im Mount-Modus — es holt die Dateien in Intervallen per WebDAV, statt den Vault live per FUSE einzuhängen. Das braucht keine `/dev/fuse`-Freigabe oder erweiterte Container-Rechte und ist damit die sicherere Variante; für ein Wissens-Repository reicht periodischer Sync völlig, Millisekunden-Aktualität ist nicht nötig.

> ⚠️ **Sicherheitshinweis:** Das Nextcloud-App-Passwort wird auf dem Server gespeichert (eigenes Volume `vault-bridge-data`), damit die Bridge selbstständig neu synchronisieren kann. Es wird vor dem Schreiben mit `rclone obscure` **verschleiert** — das ist **keine echte Verschlüsselung**, nur Schutz vor zufälligem Mitlesen. Verwende deshalb zwingend ein dediziertes App-Passwort (in Nextcloud jederzeit unabhängig vom Hauptpasswort widerrufbar), niemals dein Hauptpasswort. Standardmäßig mountet das MCP-Gateway-Dateisystem-Werkzeug den Vault **read-only** (`:ro`) — selbst falls ein Client fehlerhaft schreiben wollte, verhindert das bereits der Docker-Mount, nicht erst die App-Logik.

#### Schreibzugriff für die KI (Zwei-Wege-Sync)

Standardmäßig ist die Anbindung **nur lesend**: Nextcloud → lokal → MCP-Gateway. Willst du, dass die KI über das MCP-Dateisystem-Werkzeug auch Notizen anlegen/bearbeiten kann und diese Änderungen zurück nach Nextcloud fließen, brauchst du **zwei** Schalter gleichzeitig:

1. In der Vault-Bridge-Oberfläche: **„Zwei-Wege-Sync aktivieren"** anhaken, dann erneut „Verbinden & synchronisieren". Intern wechselt das von `rclone sync` (Einweg) zu [`rclone bisync`](https://rclone.org/bisync/) (Zwei-Wege) — beim ersten Durchlauf in diesem Modus macht die Bridge automatisch den nötigen einmaligen `--resync`-Basislauf. Konflikte (Datei auf beiden Seiten geändert) überschreibt rclone dabei **nie** kommentarlos: Beide Versionen bleiben erhalten, umbenannt mit `.path1`/`.path2`-Suffix, zur manuellen Überprüfung. (Das per `apt` installierte rclone in diesem Image ist älter als die aktuelle Doku auf rclone.org — modernere Flags wie `--conflict-resolve` oder `--fast-list` für `bisync` unterstützt es nicht, deshalb bewusst nicht verwendet.)
2. In der `.env`: `MCP_VAULT_MOUNT_MODE=rw` setzen, dann `docker compose -f docker-compose.rocm.yml up -d mcp mcpo` (Standard ist `ro`). **Beide** Dienste neu starten ist wichtig: `mcpo` hält eine laufende Session zu `mcp` — wird nur `mcp` neu erstellt, bricht diese Session ab und Werkzeugaufrufe aus Open WebUI schlagen mit `"MCP session is not available"` fehl, bis auch `mcpo` neu gestartet wird. Dieselbe Regel gilt für **jeden** Neustart/jede Neuerstellung von `mcp` (auch z. B. nach einem Image-Update) — `mcpo` danach immer mit neu starten.

> ⚠️ Nur **einen** der beiden Schalter zu setzen reicht nicht und kann zu stillem Datenverlust führen: Nur `rw` ohne Zwei-Wege-Sync heißt, die KI kann lokal schreiben, aber der nächste automatische Einweg-Sync von Nextcloud überschreibt/löscht das kommentarlos wieder. Nur Zwei-Wege-Sync ohne `rw` heißt, die KI kann trotzdem nicht schreiben (Docker blockiert es auf Mount-Ebene). Aktivier immer beide zusammen.

**Bekannte Einschränkung des `mcp`-Gateway-Images:** Bei manchen Installationen registriert `hwdsl2/mcp-gateway` das `filesystem`-Werkzeug beim allerersten Start nicht automatisch, obwohl `MCP_SERVERS=fetch,filesystem` korrekt gesetzt ist (`docker logs mcp` zeigt dann nur eine „connected client for server: fetch"-Zeile, keine für `filesystem`). Prüfen mit `docker exec mcp cat /var/lib/mcp/mcp_settings.json` — fehlt dort der `filesystem`-Eintrag unter `mcpServers`, hilft ein manueller Nachtrag:
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

Konfigurierbar über `.env`: `PORT_VAULT_BRIDGE` (Standard `8700`), `MCP_VAULT_MOUNT_MODE` (`ro`/`rw`, Standard `ro`) sowie `MCP_SERVERS`/`MCP_FILESYSTEM_DIRS` am `mcp`-Dienst, falls du weitere MCP-Werkzeuge oder -Verzeichnisse hinzufügen willst.
