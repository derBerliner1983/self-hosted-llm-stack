# Werkzeuge fürs LLM (MCP)

MCP Gateway, Anbindung an Open WebUI und die Checkliste pro Modell.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/tools.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · **Werkzeuge fürs LLM (MCP)** · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Excalidraw](excalidraw.md) · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## MCP Gateway (Werkzeuge fürs LLM)

Der Stack bringt **MCP Gateway** mit — stellt Werkzeuge wie Dateisystem, Web-Fetch, Zeit (Zeitzonen korrekt inkl. Sommerzeit, keine Modell-Kopfrechnung), GitHub, Suche und Datenbankzugriff bereit. Der Installer verdrahtet ihn automatisch mit LiteLLM (Schritt 7/8); der API-Key wird dabei automatisch erzeugt und in die `.env` geschrieben.

```bash
./scripts/wire-mcp.sh   # erneut ausführen, falls der mcp-Container neu erzeugt wurde (neuer Key)
```

#### MCP-Server verwalten (MCPHub-Oberfläche)

Im `mcp`-Container läuft [MCPHub](https://github.com/samanhappy/mcphub), das eine eigene Weboberfläche zum Verwalten der MCP-Server mitbringt — erreichbar unter `http://<server-ip>:3000` (oder über die Dashboard-Kachel „MCP Gateway"):

- **Server ansehen:** welche MCP-Server laufen, welche Werkzeuge jeder bereitstellt, Live-Logs
- **Ein-/ausschalten:** einzelne Server oder einzelne Werkzeuge deaktivieren, ohne sie zu löschen
- **Neue hinzufügen:** weitere MCP-Server eintragen — greift per Hot-Reload, ohne Container-Neustart

Angemeldet wird sich mit dem `admin`-Benutzer aus `/var/lib/mcp/mcp_settings.json`. Derselbe Port bedient auch den `/mcp`-Endpunkt für direkte MCP-Clients (Claude Desktop, Cursor …), abgesichert über den Bearer-Key aus der `.env`.

> **Nach jeder Änderung an den MCP-Servern `mcpo` neu starten** (`./scripts/restart-mcp.sh --mcpo-only`) — sonst hält `mcpo` weiter die alte Werkzeugliste und Open WebUI sieht die Änderung nicht.

Konfigurierbar über `.env`: `PORT_MCP` (Standard `3000`). `install.sh` gibt den Port **unabhängig vom Firewall-Modus nur fürs LAN** frei: Oberfläche und Endpunkt sind zwar abgesichert (Login bzw. Bearer-Key), geben aber Zugriff auf alle Werkzeuge inklusive Vault-Schreibzugriff.

## Werkzeuge in Open WebUI aktivieren (mcpo)

**Wichtig:** Open WebUI spricht kein rohes MCP-Protokoll, sondern nur **OpenAPI**. Der Stack bringt dafür `mcpo` mit (den offiziellen MCP→OpenAPI-Proxy des Open-WebUI-Teams) — er übersetzt MCP Gateway und Code-Sandbox in ein Format, das Open WebUI direkt versteht. `scripts/wire-mcp.sh` richtet auch das automatisch ein.

So bindest du die Werkzeuge in Open WebUI ein:

1. **Admin-Panel** (Zahnrad-Icon, dann **Einstellungen** → **Werkzeuge**, bzw. je nach Version **Workspace → Werkzeuge → Externe Werkzeug-Server**)
2. Neuen Werkzeug-Server hinzufügen, URL: **`http://mcpo:8000/mcp_gateway`** (Dateisystem, Web, Zeit, GitHub, Suche, DB)
3. Einen zweiten hinzufügen, URL: **`http://mcpo:8000/code_sandbox`** (`run_python`, `run_shell`)
4. Optional einen dritten, URL: **`http://mcpo:8000/android_build`** (Android-Projekte anlegen/bauen/testen — nur nötig, wenn du den `android-mcp`-Dienst nutzt)
5. Optional einen vierten, URL: **`http://mcpo:8000/excalidraw`** ([Diagramme bauen](excalidraw.md) — nur nötig, wenn du den `excalidraw-mcp`-Dienst nutzt)
6. Im Chat: Werkzeug-Icon unten im Eingabefeld → die gewünschten Werkzeuge für die Unterhaltung aktivieren

```bash
docker logs mcpo          # Läuft mcpo, sind beide Server geladen?
docker logs sandbox-mcp   # Läuft die Code-Sandbox?
docker logs litellm | grep -i mcp   # Sieht (zusätzlich) LiteLLM selbst die MCP-Server?
```

> **Hinweis:** Menüpfade und genaues Verhalten können sich je nach Open-WebUI-Version leicht unterscheiden (schnelllebiges Feld) — nach dem Deploy gemeinsam verifizieren, ob die Werkzeuge im Chat tatsächlich aufgerufen werden.

> ⚠️ **Bekannte Einschränkung (reproduziert, Stand dieser Doku):** Bei Modellen, die über eine **LiteLLM**-Verbindung laufen, formuliert Open WebUI zwar korrekt einen Werkzeugaufruf, führt ihn aber teils nie tatsächlich aus — das rohe Aufruf-JSON landet stattdessen unverändert als sichtbarer Text in der Antwort. Über eine **direkte Ollama-Verbindung** (Admin → Einstellungen → Verbindungen → „Ollama-API") lief derselbe Aufruf im Test hingegen zuverlässig durch und wurde wirklich ausgeführt. Falls Werkzeuge bei dir nur Text statt echter Ergebnisse liefern: kurz auf eine direkte Ollama-Verbindung umschalten, um zu prüfen, ob das der Unterschied ist.

#### Checkliste: Werkzeuge pro Modell freischalten

Werkzeug-Einstellungen gelten in Open WebUI **pro Modell**, nicht global — ein neu geladenes Modell startet also immer wieder ohne Werkzeuge, auch wenn ein anderes Modell längst funktioniert. Diese fünf Punkte unter **Workspace → Modelle → `<modell>` → Bearbeiten** abarbeiten:

| # | Einstellung | Wert | Warum |
|---|---|---|---|
| 1 | **Werkzeuge** | „MCP Gateway" ✓ (+ „Code Sandbox") | Ohne Häkchen kennt das Modell die Werkzeuge gar nicht |
| 2 | **Fähigkeiten → Eingebaute Werkzeuge** | **aus** | Sonst bekommt das Modell stattdessen Open WebUIs eigene Notiz-/Kalender-Werkzeuge und ignoriert die MCP-Werkzeuge |
| 3 | **Erweiterte Parameter → Funktionsaufruf** | **Standard** (nicht „Nativ") | „Nativ" setzt zuverlässiges Tool-Calling im Modell voraus; kleinere lokale Modelle scheitern daran oft stillschweigend |
| 4 | **Erweiterte Parameter → `num_ctx` (Ollama)** | **mind. `16384`** | Ollamas kleines Standard-Kontextfenster schneidet die Werkzeugliste ab — das Modell sieht dann nur die ersten paar Werkzeuge und hält den Rest für nicht existent |
| 5 | **System-Prompt** | Anweisung zur Werkzeugnutzung (Beispiel unten) | Verhindert, dass das Modell vorschnell „darauf habe ich keinen Zugriff" antwortet, statt es zu versuchen |

Beispiel für Punkt 5:

```
Du hast Zugriff auf externe Werkzeuge (Tools). Bevor du sagst, dass du etwas
nicht kannst, nicht weißt oder keinen Zugriff hast, prüfe IMMER zuerst, ob
eines deiner verfügbaren Werkzeuge die Aufgabe lösen könnte — und rufe es
dann auf. Fragen zu Dateien/Notizen/Wissensdatenbank → Dateisystem-Werkzeuge;
aktuelle Informationen/Webseiten → Web-Werkzeuge; Datum/Uhrzeit/Zeitzonen →
Zeit-Werkzeug (niemals selbst rechnen); Code testen → Sandbox-Werkzeuge;
Android-Projekte anlegen/bauen → Android-Werkzeuge (NICHT die Sandbox).
Wenn du Pfad oder Parameter nicht kennst, arbeite dich in mehreren Schritten
vor (erst auflisten/suchen, dann lesen), statt aufzugeben.

Arbeite zielgerichtet statt durch Ausprobieren: Lies die Beschreibung deiner
Werkzeuge und wähle das passende, statt dieselbe Frage mit einem
unpassenden Werkzeug immer wieder anders zu stellen. Meldet ein Werkzeug,
dass etwas nicht existiert oder nicht installiert ist, ist das eine
Antwort — probiere dann nicht dutzende Pfad- oder Befehlsvarianten durch,
sondern prüfe, ob ein ANDERES Werkzeug zuständig ist, und sag sonst dem
Nutzer klar, was fehlt. Mehr als ein paar Versuche für dieselbe Teilfrage
heißt: du suchst am falschen Ort.

Behaupte niemals, du seist eine isolierte KI ohne Zugriff — das ist hier
falsch. Wenn ein Werkzeugaufruf fehlschlägt, nenne die konkrete
Fehlermeldung.
```

> **Merke:** Ein Modell, das behauptet, ein Werkzeug existiere nicht, ist **kein** verlässlicher Beleg dafür. Diese Selbstauskünfte sind erfahrungsgemäß frei erfunden — prüf im Zweifel in der Werkzeug-Übersicht (siehe unten), was tatsächlich da ist.

#### Werkzeug-Übersicht im Browser (mcpo)

mcpo bringt eine Swagger-Oberfläche mit, die **verbindlich** zeigt, welche Werkzeuge den Modellen zur Verfügung stehen — inklusive Parameter, und direkt ausprobierbar ohne Modell dazwischen:

```
http://<server-ip>:8800/mcp_gateway/docs     # Dateisystem, Web-Fetch, Zeit, …
http://<server-ip>:8800/code_sandbox/docs    # run_python, run_shell
http://<server-ip>:8800/excalidraw/docs      # Diagramme (nur mit excalidraw-mcp)
```

(Auch als Dashboard-Kachel „mcpo".) Dieselbe Liste auf der Kommandozeile:

```bash
docker exec mcp curl -s http://mcpo:8000/mcp_gateway/openapi.json \
  | grep -oE '"/[a-zA-Z0-9_-]+"' | sort -u
```

Und ein einzelnes Werkzeug direkt testen, komplett ohne Modell — der schnellste Weg, „liegt's am Backend oder am Modell?" zu beantworten:

```bash
docker exec mcp curl -s -X POST http://mcpo:8000/mcp_gateway/filesystem-list_directory \
  -H "Content-Type: application/json" -d '{"path":"/vault"}'
```

Konfigurierbar über `.env`: `PORT_MCPO` (Standard `8800`). Der Port wird von `install.sh` **unabhängig vom Firewall-Modus nur fürs LAN** geöffnet: mcpo hat keine eigene Authentifizierung, und über seine Werkzeuge (`filesystem-write_file` & Co.) käme man an den Vault. Open WebUI erreicht mcpo ohnehin containerintern und braucht den veröffentlichten Port nicht.

#### Zeit-Werkzeug (Zeitzonen ohne Modell-Kopfrechnung)

Sprachmodelle sind bei Zeitzonen-Umrechnungen erfahrungsgemäß unzuverlässig — Sommerzeit wird vergessen, die Kopfrechnung geht schief, oder es wird ganz ohne Werkzeugaufruf eine plausibel klingende, aber falsche Zeit erfunden. Deshalb bringt der Stack ein eigenes, kleines Werkzeug mit (`mcp-tools/get_time.py`, Teil des `mcp_gateway`-Servers, kein zusätzlicher Eintrag in Open WebUI nötig): Es rechnet mit Pythons `zoneinfo` (Standardbibliothek, kennt Sommer-/Winterzeit korrekt) statt das Modell raten zu lassen. Nimmt eine Liste von IANA-Zeitzonen entgegen (z. B. `Asia/Bangkok`, `Europe/Berlin`, `America/Vancouver`), damit auch Mehrfach-Anfragen („wie spät ist es in X und Y?") in einem einzigen Aufruf zuverlässig beantwortet werden können.

Beispiel-Prompt: *„Nutze das Zeit-Werkzeug für Asia/Bangkok und Europe/Berlin."* Wie beim Fetch-Werkzeug hilft ein passender System-Prompt am Modell dabei, das Werkzeug auch ungefragt zu nutzen, wenn nach der Uhrzeit gefragt wird.

`scripts/wire-mcp.sh` trägt `filesystem` und `time` idempotent in `mcp_settings.json` nach, falls das Image sie beim ersten Start nicht selbst registriert hat (bekannte Lücke, siehe Commit-Historie) — einfach erneut ausführen, falls `docker exec mcp cat /var/lib/mcp/mcp_settings.json` einen der beiden Einträge vermissen lässt.

## MCP Gateway mit LiteLLM verbinden

LiteLLM und MCP Gateway werden bei Verwendung der Compose-Dateien in diesem Repository **automatisch verbunden** — es ist keine manuelle Schlüsseleinrichtung nötig.

API-Schlüssel werden automatisch über gemeinsame Docker-Volumes zwischen den Diensten geteilt:

- Ollama erzeugt beim ersten Start einen API-Schlüssel und kopiert ihn in ein gemeinsames Volume
- MCP Gateway macht dasselbe
- LiteLLM liest beim Start beide Schlüssel aus den gemeinsamen Volumes

Die Umgebungsvariablen `LITELLM_MCP_URL=http://mcp:3000/mcp` und `LITELLM_OLLAMA_BASE_URL=http://ollama:11434` sind in den Compose-Dateien vorkonfiguriert, sodass alle Dienste mit einem einzigen `docker compose up -d` automatisch verbunden werden.

Einmal verbunden, können KI-Clients, die LiteLLM aufrufen, MCP-Werkzeuge (Dateisystem, Fetch, GitHub usw.) direkt über den LiteLLM-Proxy nutzen.

## Beispiel für MCP-Werkzeuge

Nutze MCP Gateway, um deinem KI-Assistenten Zugriff auf Dateien, das Web und GitHub zu geben:

MCP Gateway ist standardmäßig intern im Docker-Netzwerk. Bevor du `http://localhost:3000/mcp` von einem host-seitigen KI-Client oder host-seitigem `curl` nutzt, kommentiere die Port-Zuordnung `3000:3000/tcp` für den `mcp`-Dienst in `docker-compose.yml` aus und starte ihn neu.

```bash
MCP_KEY=$(docker exec mcp mcp_manage --getkey)

# MCP-Endpunkt mit einem KI-Client nutzen (z. B. Cline in VS Code)
# Setze die MCP-Server-URL: http://localhost:3000/mcp
# Setze den Authorization-Header: Bearer <api_key>

# Oder teste den MCP-Endpunkt direkt mit einer initialize-Anfrage
curl -s http://localhost:3000/mcp \
    -X POST \
    -H "Authorization: Bearer $MCP_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```
