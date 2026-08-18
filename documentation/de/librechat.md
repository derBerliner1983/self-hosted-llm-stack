# LibreChat (zweite Chat-Oberfläche)

Alternative zu Open WebUI — spricht MCP direkt, ohne den Umweg über mcpo.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/librechat.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · **LibreChat (zweite Oberfläche)** · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Warum eine zweite Oberfläche?

[LibreChat](https://www.librechat.ai/) ist eine zweite Chat-Oberfläche, die **parallel** zu Open WebUI läuft — auf demselben LiteLLM, mit denselben Modellen und denselben Werkzeugen. Du musst dich nicht entscheiden: beide sind gleichzeitig erreichbar, jede mit eigenem Login und eigener Chat-Historie.

Der praktische Unterschied liegt bei den Werkzeugen:

| | Open WebUI | LibreChat |
|---|---|---|
| Modelle | über LiteLLM | über LiteLLM (dieselben) |
| MCP-Werkzeuge | nur über **mcpo** (MCP → OpenAPI) | **direkt**, MCP nativ |
| Werkzeuge freischalten | pro Modell, [fünf Einstellungen](werkzeuge.md#checkliste-werkzeuge-pro-modell-freischalten) | im Chat pro Unterhaltung |
| Werkzeugnamen im Chat | umbenannt (`tool_run_script_post`) | Originalname (`run_script`) |

Open WebUI versteht **kein** rohes MCP, nur OpenAPI — deshalb steht `mcpo` als Übersetzer dazwischen (Details: [Werkzeuge fürs LLM](werkzeuge.md#werkzeuge-in-open-webui-aktivieren-mcpo)). Dieser Zwischenschritt kostet Stabilität:

- `mcpo` hält offene Sitzungen zu `mcp`, `sandbox-mcp` und `android-mcp`. Startet einer dieser Dienste neu, ohne dass `mcpo` mit neu startet, liefern die Werkzeuge `MCP session is not available` — dafür gibt es extra [`scripts/restart-mcp.sh`](betrieb.md).
- `mcpo` benennt Werkzeuge um. Das Modell sieht `tool_run_script_post`, nicht `run_script` — ein Prompt, der ein Werkzeug beim Namen nennt, geht deshalb ins Leere.

**LibreChat spricht MCP nativ.** Beide Punkte entfallen: keine Übersetzungsschicht, keine umbenannten Werkzeuge, keine abgerissenen Sitzungen. Genau dafür ist es hier eingebaut — als Vergleichsmöglichkeit, wenn Werkzeugaufrufe in Open WebUI zicken.

Was LibreChat sonst noch mitbringt: **Agenten** (mehrstufige Abläufe mit fest zugewiesenen Werkzeugen), **Verzweigungen** im Gesprächsverlauf, und Antworten mehrerer Modelle nebeneinander in einer Unterhaltung.

## Erste Schritte

LibreChat startet zusammen mit dem Rest des Stacks — `install.sh` legt alle nötigen Schlüssel in der `.env` an, es ist kein zusätzlicher Schritt nötig.

```bash
docker compose -f docker-compose.rocm.yml up -d librechat librechat-mongo
docker logs -f librechat        # erster Start dauert etwas
```

Dann im Browser öffnen:

```
http://<server-ip>:3080
```

(Auch als Dashboard-Kachel „LibreChat".)

**Die Zugangsdaten legt der Installer an** — du musst dich nicht erst registrieren. Anzeigen:

```bash
./scripts/show-credentials.sh          # Abschnitt LibreChat
./scripts/librechat-user.sh --show     # nur LibreChat
```

Im [Kontrollzentrum](kontrollzentrum.md) steht dasselbe unter **LibreChat → Zugangsdaten anzeigen**.

| | |
|---|---|
| E-Mail | `admin@stack.local` (änderbar über `LIBRECHAT_ADMIN_EMAIL`) |
| Passwort | einmalig zufällig erzeugt, steht in der `.env` |

Das Passwort ist bewusst **nicht** fest eingebaut: LibreChat kommt über die MCP-Werkzeuge an deinen Vault, da wäre ein bekanntes Standardpasswort die schlechteste Idee im ganzen Stack. Ändere es nach der ersten Anmeldung in LibreChat selbst.

Die Registrierung ist deshalb von vornherein **zu** (`LIBRECHAT_ALLOW_REGISTRATION=false`). Sollen sich weitere Leute selbst anmelden können:

```bash
sed -i 's/^LIBRECHAT_ALLOW_REGISTRATION=.*/LIBRECHAT_ALLOW_REGISTRATION=true/' .env
docker compose -f docker-compose.rocm.yml up -d librechat
```

Weiteres Konto von Hand anlegen (LibreChats eigenes Kommando):

```bash
docker exec -it librechat npm run create-user
docker exec librechat npm run list-users
```

Wurde das Erstkonto beim Installieren nicht angelegt — etwa weil LibreChat noch nicht bereit war — hol es nach:

```bash
./scripts/librechat-user.sh
```

## Werkzeuge im Chat nutzen

Anders als in Open WebUI gibt es **keine Konfiguration pro Modell**. Die MCP-Dienste stehen aus `librechat/librechat.yaml` heraus schon bereit; du wählst sie pro Unterhaltung aus:

1. Neue Unterhaltung, Modell auswählen (Endpunkt **„LiteLLM"**)
2. Im Eingabebereich das Werkzeug-Symbol anklicken
3. Die gewünschten Server aktivieren — `mcp_gateway`, `code_sandbox`, `android_build`

Danach kannst du normal fragen: *„Schau in meiner Wissensdatenbank nach, was unter 01inbox liegt"* oder *„Schreib ein Bash-Skript, das … — führ es aus und zeig mir die echte Ausgabe."*

> **Werkzeugnamen trotzdem nicht im Prompt nennen.** Auch wenn LibreChat die Originalnamen durchreicht: Beschreib lieber die Aufgabe („führ es aus und zeig die echte Ausgabe") als das Werkzeug. Das Modell wählt dann selbst — und wählt bei einem Namen, den es nicht findet, sonst gar nichts.

Die drei Server sind dieselben wie in Open WebUI:

| Server | Was er kann | Doku |
|---|---|---|
| `mcp_gateway` | Dateisystem (`/vault`, `/workspace`), Web-Abruf, Zeitzonen, GitHub, Suche, DB | [Werkzeuge fürs LLM](werkzeuge.md) |
| `code_sandbox` | Code ausführen und testen (Python, Shell, Java, Go, C++, optional PowerShell) | [Code-Sandbox](code-sandbox.md) |
| `android_build` | Android-Projekte anlegen, bauen, testen | [Android-Entwicklung](android.md) |

Die Beschreibungen, die das Modell zu jedem Server sieht (`serverInstructions` in der YAML), sagen ihm auch, was **nicht** da ist — kein Netz in der Sandbox, `/work` bleibt erhalten, `/tmp` nicht. Das erspart die endlosen Rateschleifen, die entstehen, wenn ein Modell die Grenzen seiner Werkzeuge nicht kennt.

## Symbole und Namen der Modelle

In Open WebUI klickst du ein Modell an und änderst Bild und Namen im Bearbeiten-Fenster. LibreChat kennt das nicht — hier steht es in [`librechat/librechat.yaml`](../../librechat/librechat.yaml). Dafür gilt es dann für alle Nutzer gleich.

Zwei Ebenen:

**Ganzer Endpunkt** — ein Symbol für alle Modelle darunter:

```yaml
endpoints:
  custom:
    - name: "LiteLLM"
      iconURL: "/images/litellm.png"
      modelDisplayLabel: "LiteLLM (lokal)"
```

**Einzelne Modelle** — über `modelSpecs`. Jeder Eintrag ist ein Steckbrief mit eigenem Namen, Symbol und Beschreibung; `preset` legt fest, welches Modell dahintersteckt:

```yaml
modelSpecs:
  enforce: false      # normale Modellliste bleibt zusätzlich wählbar
  prioritize: true    # Steckbriefe stehen oben in der Auswahl
  list:
    - name: "gemma-lokal"
      label: "Gemma 3 12B"
      description: "Allrounder, läuft auf der eigenen GPU"
      iconURL: "/images/gemma.png"
      showIconInMenu: true
      showIconInHeader: true
      order: 1
      preset:
        endpoint: "LiteLLM"
        model: "ollama/gemma3:12b"
```

Ein auskommentiertes Beispiel steht schon in der Datei — Zeilen einkommentieren, anpassen, neu starten.

### Wo die Bilder hingehören

`iconURL` nimmt dreierlei:

| Wert | Bedeutung |
|---|---|
| `/images/custom/gemma.png` | Eigene Datei aus dem Ordner `images/` |
| `https://…/logo.png` | Beliebige Adresse im Netz |
| `openAI`, `google`, `anthropic` … | Ein mitgeliefertes Symbol wiederverwenden |

Eigene Bilder gehören in den Ordner **`images/`** im Projektverzeichnis. Der ist read-only in den Container eingehängt; LibreChat liefert alles darin unter `/images/custom/` aus:

```bash
cp mein-logo.png ~/self-hosted-llm-stack/images/
# in der YAML dann:  iconURL: "/images/custom/mein-logo.png"
```

Kein `docker cp` nötig, und beim Neuerzeugen des Containers bleiben die Bilder erhalten. Ein **neues Bild** ist sofort da (Seite neu laden); nur eine Änderung an der YAML braucht einen Neustart.

Quadratische PNG oder SVG ab etwa 128×128 sehen am besten aus.

> Nach jeder Änderung an der YAML ist ein Neustart von `librechat` nötig — die Datei wird nur beim Start gelesen.

## Wo MCP konfiguriert wird — und was tun, wenn Werkzeuge fehlen

Ein Suchfeld für MCP gibt es in LibreChat nicht: die Server stehen in [`librechat/librechat.yaml`](../../librechat/librechat.yaml) unter `mcpServers`. Was du in der Oberfläche wählst, ist nur, *welche* der dort verbundenen Werkzeuge eine Unterhaltung oder ein Agent benutzen darf.

**Wichtig:** LibreChat verbindet die MCP-Server **beim Start**. Lief ein Dienst damals noch nicht — oder wurde er seither neu erzeugt, etwa durch `restart-mcp.sh` —, bleibt er für LibreChat verschwunden, bis LibreChat selbst neu startet:

```bash
docker compose -f docker-compose.rocm.yml restart librechat
```

### Fehler: `AGENT_EXPECTED_MCP_TOOLS_UNAVAILABLE`

Ein **Agent** hat MCP-Werkzeuge zugewiesen, LibreChat konnte aber keinen MCP-Server verbinden. Die Fehlersuche geht die ganze Kette durch:

```bash
./scripts/diagnose-mcp.sh
```

(Auch im [Kontrollzentrum](kontrollzentrum.md) an jedem MCP-Dienst unter **Werkzeuge prüfen**.)

Geprüft wird: laufen die Dienste, ist `MCP_API_KEY` gesetzt **und im Container angekommen**, antworten die Dienste auf eine echte MCP-`initialize`-Anfrage aus dem LibreChat-Container heraus, was steht im Log, und ist der `mcpServers`-Block überhaupt in der Konfiguration.

Die häufigsten drei Ursachen:

| Ursache | Behebung |
|---|---|
| LibreChat startete vor den MCP-Diensten | `docker compose -f docker-compose.rocm.yml restart librechat` |
| `MCP_API_KEY` fehlt oder ist im Container leer | `./scripts/wire-mcp.sh`, dann `docker compose … up -d --force-recreate librechat` |
| Der Agent selbst hat keine Werkzeuge ausgewählt | Agenten → Bearbeiten → Werkzeuge |

> Der letzte Punkt erklärt, warum es „ohne MCP" funktioniert: ohne zugewiesene Werkzeuge antwortet das Modell einfach aus sich heraus.

### Web-Suche

Die Werkzeuge des MCP Gateways enthalten **Fetch**, nicht Suche: Fetch holt eine Seite, deren Adresse schon bekannt ist. Eine Frage wie „such im Netz nach …" kann es damit nicht beantworten — dafür fehlt eine Suchmaschine.

Zwei Wege: LibreChats eigene Web-Suche (`webSearch` in der YAML, braucht einen Zugang bei einem Suchanbieter) oder ein eigener MCP-Suchserver, den du unter `mcpServers` einträgst. Beides ist in diesem Stack noch nicht eingerichtet.

## Konfiguration anpassen

Alles Inhaltliche steht in [`librechat/librechat.yaml`](../../librechat/librechat.yaml) — Endpunkte, MCP-Server, Oberflächenoptionen. Nach jeder Änderung:

```bash
docker compose -f docker-compose.rocm.yml restart librechat
```

Die Modellliste wird zur Laufzeit von LiteLLM geholt (`fetch: true`). Ein neues Modell, das du bei LiteLLM registrierst ([Modelle verwalten](modelle.md)), taucht in LibreChat automatisch auf — die YAML muss dafür nicht angefasst werden.

`.env`-Schalter:

| Variable | Standard | Bedeutung |
|---|---|---|
| `PORT_LIBRECHAT` | `3080` | Port der Oberfläche |
| `LIBRECHAT_ALLOW_REGISTRATION` | `false` | Registrierung zu; das Erstkonto legt der Installer an |
| `LIBRECHAT_ADMIN_EMAIL` | `admin@stack.local` | Anmeldename des Erstkontos |
| `LIBRECHAT_ADMIN_PASSWORD` | erzeugt | Passwort des Erstkontos |
| `LIBRECHAT_CREDS_KEY` / `_IV` | erzeugt | Verschlüsselung gespeicherter Zugangsdaten (64 bzw. 32 Hex-Zeichen) |
| `LIBRECHAT_JWT_SECRET` / `_REFRESH_SECRET` | erzeugt | Sitzungs-Token |

> Die vier Schlüssel erzeugt `install.sh` einmalig. **Nicht nachträglich ändern** — sonst sind gespeicherte Zugangsdaten unlesbar und alle Anmeldungen fliegen raus. Wenn du sie doch tauschen musst: alle Nutzer melden sich neu an.

## LibreChat wieder loswerden

Nichts davon ist Pflicht — Open WebUI läuft unabhängig weiter.

```bash
docker compose -f docker-compose.rocm.yml stop librechat librechat-mongo
```

Dauerhaft: die beiden Dienste in `docker-compose.rocm.yml` auskommentieren. Die Daten liegen in den Volumes `librechat-mongo`, `librechat-data` und `librechat-uploads` und bleiben erhalten, bis du sie löschst:

```bash
docker volume rm librechat-mongo librechat-data librechat-uploads   # löscht Konten und Verlauf
```

## Wenn es hakt

```bash
docker logs librechat --tail 50
docker logs librechat-mongo --tail 20
```

| Symptom | Ursache |
|---|---|
| Container startet nicht, Meldung zu `CREDS_KEY` | Schlüssel fehlt oder hat die falsche Länge — 64 Hex-Zeichen für `CREDS_KEY`, 32 für `CREDS_IV`. Neu erzeugen: `openssl rand -hex 32` bzw. `-hex 16` |
| Keine Modelle in der Auswahl | LiteLLM erreichbar? `docker exec librechat curl -s http://litellm:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"` |
| Werkzeuge fehlen im Chat | `docker logs librechat \| grep -i mcp` — meldet beim Start, welche MCP-Server verbunden wurden |
| `mcp_gateway` verbindet nicht | `MCP_API_KEY` in der `.env` gesetzt? Sonst `./scripts/wire-mcp.sh` ausführen |
| Anmeldung nicht möglich, Meldung „registration disabled“ | So gewollt — melde dich mit den Zugangsdaten aus `show-credentials.sh` an, oder setz `LIBRECHAT_ALLOW_REGISTRATION=true` |
| Zugangsdaten funktionieren nicht | Wurde das Konto angelegt? `docker exec librechat npm run list-users`. Nachholen: `./scripts/librechat-user.sh` |

## Sicherheit

Für LibreChat gilt dasselbe wie für Open WebUI und das Dashboard: **nicht ungeschützt ins Internet stellen.** `install.sh` gibt Port `3080` im Modus `lan` nur fürs lokale Netz frei. Für den Zugriff von außen gehört ein Reverse-Proxy mit Login und MFA davor — siehe [Sicherheit & Fernzugriff](sicherheit.md).

Der Chat hat über `code_sandbox` und `android_build` Zugriff auf Code-Ausführung und über `mcp_gateway` **Schreibzugriff auf den Vault**. Ein offener Zugang ist damit gleichbedeutend mit Zugriff auf deine Wissensdatenbank.
