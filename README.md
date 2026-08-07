[Deutsch](README.md) | [English](README-en.md)

# Self-Hosted AI Stack

[![Powered by Docker Compose](docs/images/powered-by-docker-compose.svg)](https://docs.docker.com/compose/) &nbsp;[![Docker Pulls](https://raw.githubusercontent.com/hwdsl2/badges/main/img/docker-pulls-ai-stack.svg)](https://hub.docker.com/u/hwdsl2) &nbsp;[![License: MIT](docs/images/license.svg)](https://opensource.org/licenses/MIT)

<p align="center">
  <img src="docs/images/self-hosted-ai-stack-overview.png"
       alt="Self-Hosted AI Stack: Stelle einen kompletten selbst gehosteten KI-Stack mit einem einzigen Befehl bereit"
       width="100%">
</p>
<p align="center"><sub>Zeigt das allgemeine Konzept der ursprünglichen CPU-/NVIDIA-Variante. Das aktuelle Architekturdiagramm für den AMD-ROCm-Stack findest du im <a href="#architektur">Architektur-Abschnitt</a> weiter unten.</sub></p>

Enthält Ollama, LiteLLM, AnythingLLM, Whisper, MCP Gateway, Embeddings, Docling und Kokoro — vollständig konfiguriert und startklar mit Docker Compose.

- Ohne Konfiguration: Alle Dienste konfigurieren sich beim ersten Start automatisch
- Standardmäßig sicher: Der Passwortschutz von AnythingLLM ist aktiviert, und die mitgelieferten API-Dienste erzeugen automatisch Schlüssel
- HTTPS-bereit: Ein optionales Caddy-Overlay stellt automatisches TLS bereit und bindet direkte HTTP-Ports an localhost
- Privat: Läuft standardmäßig lokal, mit optionaler Unterstützung externer Anbieter über LiteLLM
- Flexibel: Passe Modelle, Ports, Anbieter und API-Schlüssel über einfache env-Dateien an
- [Leichtgewichtige Stacks](#leichtgewichtige-stacks) für geringere Speicheranforderungen (ab ~4,5 GB)
- **GPU-Beschleunigung über AMD ROCm** — optimiert für den **Ryzen AI Max+ 395** (Strix Halo, gfx1151)
- Ein-Befehl-[Installer](#schnellstart-amd-rocm--empfohlen), der Hardware prüft, Firewall einrichtet und das Standardmodell lädt
- [Modernes Status-Dashboard](#dashboard) — sieh auf einen Blick, was online ist, und springe direkt drauf
- Multi-Arch: `linux/amd64`, `linux/arm64`

## Community

- 📬 [Für Projekt-Updates anmelden](https://selfhostedstack.beehiiv.com/subscribe?utm_campaign=ai) (1–2 E-Mails/Monat) — erhalte kostenlose Anleitungen zur Bereitstellung von KI und VPN (PDF)
- 💬 Tritt der [r/selfhostedstack](https://www.reddit.com/r/selfhostedstack/) Community für Diskussionen und Showcases bei
- ⭐ Gib dem Repository einen Stern, wenn du es nützlich findest — das hilft anderen, es zu entdecken

Self-Hosted AI Stack wird vom Autor von [Setup IPsec VPN](https://github.com/hwdsl2/setup-ipsec-vpn) (28k+ Sterne) gepflegt.

## Schnellstart (AMD ROCm) — empfohlen

Diese Variante ist komplett auf **Upstream-Images** umgebaut und für **AMD-GPUs** ausgelegt (getestet für den **Ryzen AI Max+ 395** / Strix Halo). Sie nutzt:

- **[Ollama (ROCm)](https://hub.docker.com/r/ollama/ollama)** als LLM-Engine mit AMD-GPU-Beschleunigung
- **[Open WebUI](https://github.com/open-webui/open-webui)** als Chat-Oberfläche (ersetzt AnythingLLM)
- **[LiteLLM](https://github.com/BerriAI/litellm)** als AI-Gateway, **MCP Gateway** + **Code-Sandbox** (Werkzeuge, inkl. `run_python`/`run_shell` zum Selbsttesten), **PostgreSQL/pgvector**, **Whisper** (STT) und **Embeddings** (TEI)
- ein **[modernes Status-Dashboard](#dashboard)**, das den Live-Status aller Dienste zeigt

Alles wird über ein einziges Skript geprüft und eingerichtet:

```bash
git clone https://github.com/derBerliner1983/self-hosted-llm-stack
cd self-hosted-llm-stack

# Optional: erst nur prüfen, ohne etwas zu ändern
./install.sh --check-only

# Installieren (prüft Hardware/ROCm, richtet Firewall ein, lädt das Modell, startet alles)
sudo ./install.sh
```

Das Install-Skript:

- prüft **System, RAM und freien Speicher**
- prüft die **AMD-GPU/ROCm** (`amdgpu`-Modul, `/dev/kfd`, `/dev/dri`, `video`/`render`-Gruppen) und fügt deinen Benutzer den GPU-Gruppen hinzu
- installiert bei Bedarf **Docker** und **Docker Compose**
- richtet die **Firewall (ufw)** ein — standardmäßig **nur LAN** (SSH offen, Web-UIs nur aus deinem lokalen Subnetz)
- schreibt eine `.env` mit automatisch erzeugten **Secrets** (Postgres-Passwort, LiteLLM-Master-Key)
- startet den Stack, **lädt das Standardmodell** und **trägt alle Modelle bei LiteLLM ein**

**Standardmodell:** `gemma4:12b` (in der `.env` mit einer Zeile änderbar, z. B. `DEFAULT_MODEL=qwen2.5:14b`). Ein anderes Modell wählst du auch direkt beim Aufruf:

```bash
DEFAULT_MODEL=llama3.1:8b sudo ./install.sh
```

> **Automatischer Fallback:** Falls `gemma4:12b` (noch) nicht in der Ollama-Bibliothek liegt, zieht der Installer automatisch das **Fallback-Modell** `gemma3:12b` (über `FALLBACK_MODEL` in der `.env` änderbar), damit nie ohne Modell gestartet wird. Sobald `gemma4:12b` verfügbar ist, lädst du es mit `docker exec ollama ollama pull gemma4:12b` nach.

Nach der Installation:

| Dienst | URL |
|---|---|
| **Dashboard** (Status-Übersicht) | `http://<server-ip>:8600` |
| **Chat** (Open WebUI) | `http://<server-ip>:3001` (Admin = erster registrierter Account) |
| **LiteLLM-Admin-UI** | `http://<server-ip>:4000/ui` (Login `admin` + Master-Key, siehe unten) |

### Architektur

```mermaid
graph LR
    U["👤 Benutzer"] -->|Chat| W["Open WebUI<br/>(Port 3001)"]
    U -->|Status| DASH["Dashboard<br/>(Port 8600)"]
    W -->|OpenAI-API| L["LiteLLM<br/>(AI-Gateway, Port 4000)"]
    L -->|routet zu| O["Ollama<br/>(ROCm, AMD-iGPU)"]
    L -->|Werkzeuge| M["MCP Gateway<br/>(Dateisystem, Web, GitHub)"]
    L -->|Werkzeuge| S["Code-Sandbox<br/>(run_python/run_shell)"]
    L -->|Metadaten| DB[("PostgreSQL<br/>+ pgvector")]
    A["🎤 Audio"] --> WH["Whisper<br/>(Sprache → Text)"]
    D["📄 Dokumente"] --> E["Embeddings<br/>(Text → Vektoren)"]
    DASH -.->|liest Status| SOCK[("Docker-Socket<br/>(nur lesend)")]
```

**Zugangsdaten anzeigen**

```bash
./scripts/show-credentials.sh
```

Zeigt alle URLs, den LiteLLM-Master-Key, das Postgres-Passwort und den MCP-API-Key direkt aus deiner `.env` an — kein `docker exec ... _manage` nötig (das gibt es nur in den alten `hwdsl2`-Images, nicht in den hier verwendeten Upstream-Images). Open WebUI hat kein vorgegebenes Passwort: Der **erste Account**, den du unter `http://<server-ip>:3001` registrierst, wird automatisch Admin.

### Dashboard

Der Stack bringt ein eigenes, schlankes **modernes Status-Dashboard** mit (`dashboard/`). Es liest den Docker-Socket (nur lesend) und zeigt in Echtzeit, **welche Dienste online sind, auf welchem Port sie laufen** und verlinkt direkt darauf. Es aktualisiert sich automatisch und ist unter `http://<server-ip>:8600` erreichbar.

### MCP Gateway (Werkzeuge fürs LLM)

Der Stack bringt **MCP Gateway** mit — stellt LLM-Anfragen über LiteLLM Werkzeuge wie Dateisystem, Web-Fetch, GitHub, Suche und Datenbankzugriff zur Verfügung. Der Installer verdrahtet ihn automatisch mit LiteLLM (Schritt 7/8); der API-Key wird dabei automatisch erzeugt und in die `.env` geschrieben.

```bash
./scripts/wire-mcp.sh   # erneut ausführen, falls der mcp-Container neu erzeugt wurde (neuer Key)
```

> **Hinweis:** Ob dein Chat-Client (z. B. Open WebUI) die von LiteLLM bereitgestellten MCP-Werkzeuge automatisch nutzt, hängt von dessen MCP-Unterstützung ab — das ist ein sich schnell entwickelndes Feld. Prüfe nach der Einrichtung mit `docker logs litellm | grep -i mcp`, ob die Verbindung zum Gateway steht.

### Code-Sandbox (`run_python` / `run_shell` fürs LLM)

Zusätzlich zu MCP Gateway bringt der Stack eine eigene **Code-Sandbox** mit (`sandbox-mcp/`), damit das Modell selbst geschriebenen Code **testen, Fehler erkennen und iterativ korrigieren** kann, statt ungetesteten Code auszugeben. Zwei Werkzeuge, über denselben LiteLLM-MCP-Mechanismus bereitgestellt:

- `run_python(code)` — führt Python-Code aus
- `run_shell(command)` — führt einen Shell-Befehl aus

**Wie die Isolation funktioniert:** Jeder einzelne Aufruf startet einen **komplett neuen, isolierten Wegwerf-Container** — kein Netzwerkzugriff, schreibgeschütztes Dateisystem (nur `/tmp` beschreibbar), Speicher-/CPU-/Prozess-Limits, kein root, alle Linux-Capabilities entfernt, Zeitlimit (Standard 15 s, maximal 60 s). Nach jedem Lauf wird der Container sofort gelöscht — es gibt also **keinen Zustand zum Zurücksetzen**: jeder Aufruf startet garantiert bei null.

> ⚠️ **Sicherheitshinweis:** Damit der Sandbox-Dienst pro Aufruf einen frischen Container starten kann, braucht er Zugriff auf den **Docker-Socket** des Hosts (`/var/run/docker.sock`). Das ist mächtig — wer diesen internen Dienst erreichen kann, kann im Prinzip beliebige Container auf dem Host starten. Der Dienst ist deshalb bewusst **nur intern** im Docker-Netz erreichbar, ohne Port nach außen. Für ein Einzelnutzer-Setup im eigenen LAN ist das ein vertretbarer Kompromiss; falls du diese Fähigkeit nicht willst, entferne einfach den `sandbox-mcp`-Dienst (und den zugehörigen `code_sandbox`-Eintrag in `litellm/config.yaml`) und starte den Stack neu.

Konfigurierbar über `.env`: `SANDBOX_IMAGE` (Basis-Image der Sandbox, Standard `python:3.12-slim`), `SANDBOX_DEFAULT_TIMEOUT`, `SANDBOX_MAX_TIMEOUT`, `SANDBOX_MEM_LIMIT`, `SANDBOX_NETWORK` (Standard `none`; z. B. `bridge` setzen, falls der Code Internetzugriff braucht — dann verlierst du den Netzwerk-Isolationsschutz).

```bash
docker logs sandbox-mcp        # Läuft der Dienst?
docker logs litellm | grep -i mcp   # Sieht LiteLLM beide MCP-Server (mcp_gateway + code_sandbox)?
```

> Wie beim MCP Gateway gilt: Ob dein Chat-Client die Werkzeuge tatsächlich beim Programmieren einsetzt (statt nur auf Anfrage), hängt von dessen Tool-Use-Verhalten ab — nach dem Deploy gemeinsam verifizieren.

### Modelle bei LiteLLM eintragen

Jedes Modell, das du mit `ollama pull` lädst, kannst du automatisch bei LiteLLM registrieren lassen — so taucht es sofort im Gateway und in Open WebUI auf:

```bash
docker exec ollama ollama pull qwen2.5:14b
./scripts/sync-ollama-models.sh
```

Das Skript ist **idempotent**: bereits eingetragene Modelle werden übersprungen, nur neue kommen hinzu.

### Nützliche Befehle

```bash
./scripts/show-credentials.sh                                 # URLs, Master-Key, Passwörter
./scripts/wire-mcp.sh                                         # MCP Gateway (neu) mit LiteLLM verdrahten
docker compose -f docker-compose.rocm.yml ps                  # Status
docker compose -f docker-compose.rocm.yml logs -f open-webui  # Logs eines Dienstes
docker compose -f docker-compose.rocm.yml down                # Stoppen (Daten bleiben in Volumes)
```

### Deinstallieren

Das Install-Skript kann auch aufräumen — sowohl den neuen ROCm-Stack als auch den **alten** Stack (AnythingLLM/`hwdsl2`-Images):

```bash
sudo ./install.sh --uninstall   # Container & Netzwerke entfernen, Daten (Volumes) behalten
sudo ./install.sh --purge       # ALLES entfernen: auch Modelle, Chats, Datenbank und .env
```

`--purge` ist unwiderruflich und fragt vorher zur Sicherheit nach (Bestätigung mit »loeschen«; mit `-y` überspringst du die Rückfrage). Firewall-Regeln bleiben unberührt.

> Die folgenden Abschnitte beschreiben den **ursprünglichen CPU-/NVIDIA-Stack** (mit den `hwdsl2/*`-Images und AnythingLLM). Für AMD nutzt du den ROCm-Schnellstart oben.

## Enthaltene Dienste

| Dienst | Rolle | Standard-Port |
|---|---|---|
| **[Ollama (LLM)](https://github.com/hwdsl2/docker-ollama)** | Führt lokale LLM-Modelle aus (llama3, qwen, mistral usw.) | `11434` |
| **[AnythingLLM](https://github.com/mintplex-labs/anything-llm)** | Web-basierte Chat-Oberfläche — standardmäßig passwortgeschützt | `3001` |
| **[LiteLLM](https://github.com/hwdsl2/docker-litellm)** | KI-Gateway mit Admin-UI — leitet Anfragen an Ollama und 100+ Anbieter weiter | `4000` |
| **[Embeddings](https://github.com/hwdsl2/docker-embeddings)** | Wandelt Text in Vektoren um für semantische Suche und RAG | `8000` |
| **[Whisper (STT)](https://github.com/hwdsl2/docker-whisper)** | Transkribiert gesprochenes Audio in Text | `9000` |
| **[WhisperLive (Echtzeit-STT)](https://github.com/hwdsl2/docker-whisper-live)** | Echtzeit-Transkription von Sprache zu Text über WebSocket | `9090` |
| **[Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro)** | Wandelt Text in natürlich klingende Sprache um | `8880` |
| **[MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway)** | Stellt MCP-Werkzeuge (Dateisystem, Fetch, GitHub, Suche, Datenbanken) für KI-Clients bereit | `3000` |
| **[Docling](https://github.com/hwdsl2/docker-docling)** | Wandelt Dokumente (PDF, DOCX usw.) in strukturierten Text/Markdown um | `5001` |

## Schnellstart

**Voraussetzungen:**

- Ein Linux-Server (lokal oder in der Cloud) mit installiertem Docker
- Mindestens 8 GB RAM (mit kleinen Modellen). Für größere LLM-Modelle (8B+) werden 16 GB oder mehr empfohlen.
- Du kannst nicht benötigte Dienste auskommentieren, um den Speicherverbrauch zu reduzieren.

**Den vollständigen Stack starten:**

```bash
# Klone das Repository, um die Compose-Dateien zu erhalten
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack
docker compose up -d
```

> **Bestehende Installationen:** Wenn du dieses Projekt geklont hast, bevor es von `docker-ai-stack` umbenannt wurde, funktionieren dein vorhandener Checkout und deine Bereitstellung weiterhin. GitHub leitet die alte Repository-URL um, und du musst dein lokales Verzeichnis, deine Container, Volumes oder Netzwerke nicht umbenennen.

> **PostgreSQL-Zugangsdaten:** Neue Installationen und bestehende Standardinstallationen werden automatisch behandelt. Wenn du zuvor ein eigenes Datenbankpasswort festgelegt hast, siehe [PostgreSQL-Zugangsdaten](#postgresql-zugangsdaten), bevor du startest.

**Ein Modell herunterladen** (erforderlich, bevor LLM-Anfragen gestellt werden):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

Führe den Health-Check aus, um zu überprüfen, ob alle Dienste funktionieren:

```bash
./stack-check.sh
```

> **Tipp:** Beim ersten Start kann die Initialisierung der Dienste einige Minuten dauern. Wenn Prüfungen fehlschlagen, warte und führe `./stack-check.sh` erneut aus. Nutze `docker compose logs`, um den Fortschritt zu prüfen.

Für detaillierte Fehlerbehebung siehe die Anleitung zur [Fehlerbehebung](docs/troubleshooting.md).

**Den LiteLLM-Masterschlüssel abrufen** (wird zum Anmelden in der Admin-UI und für LLM-Anfragen verwendet):

```bash
docker exec litellm litellm_manage --showkey
```

<details>
<summary>Kern-API-Schlüssel anzeigen (Ollama, LiteLLM, MCP Gateway)</summary>

```bash
docker exec ollama ollama_manage --showkey
docker exec litellm litellm_manage --showkey
docker exec mcp mcp_manage --showkey
```

</details>

**Auf AnythingLLM (Chat-UI) zugreifen:**

AnythingLLM ist vorkonfiguriert, um sich über LiteLLM mit deinem lokalen LLM zu verbinden. Beim ersten Start kann es einige Minuten dauern, bis es verfügbar ist (prüfe den Fortschritt mit `docker logs anythingllm`).

**Standardmäßig passwortgeschützt.** Beim ersten Start wird ein zufälliges Admin-Passwort automatisch erzeugt, einmalig in `docker logs anythingllm` ausgegeben und in `/app/server/storage/.initial_admin_password` innerhalb des `anythingllm-data`-Volumes gespeichert. Das voreingestellte Passwort bleibt über Container-Upgrades hinweg erhalten. Ändere es jederzeit unter **Settings → Security**; danach stimmt `.initial_admin_password` möglicherweise nicht mehr mit dem aktuellen Anmeldepasswort überein.

Das automatisch erzeugte Passwort abrufen:

```bash
# Jederzeit aus dem Daten-Volume:
docker exec anythingllm cat /app/server/storage/.initial_admin_password

# Oder aus den Live-Logs (nur beim ersten Start angezeigt):
docker compose logs anythingllm | grep -A4 "FIRST RUN"
```

Öffne `http://<server-ip>:3001` in deinem Browser und melde dich mit dem obigen Passwort an.

> **Tipp:** Wenn du AnythingLLM über `localhost` oder ein vertrauenswürdiges LAN hinaus verfügbar machst, nutze das mitgelieferte Caddy-HTTPS-Overlay, damit das Passwort während der Übertragung verschlüsselt wird und direkte HTTP-Ports an localhost gebunden sind. Siehe [Ins Internet gerichtete Bereitstellungen](#ins-internet-gerichtete-bereitstellungen) weiter unten.

**Auf die LiteLLM-Admin-UI zugreifen:**

Öffne `http://<server-ip>:4000/ui` in deinem Browser. Melde dich mit dem Benutzernamen `admin` und deinem LiteLLM-Masterschlüssel als Passwort an. Die UI bietet Verwaltung virtueller Schlüssel, Ausgabenverfolgung und Modellkonfiguration.

> **Tipp:** Klicke in der Admin-UI im linken Menü auf **Playground**. Wähle ein lokales Modell (z. B. `ollama-chat/llama3.2:3b`) aus dem Dropdown-Menü und beginne zu chatten — eine schnelle Möglichkeit, um zu überprüfen, ob dein lokales LLM durchgängig funktioniert.

**Den Stack stoppen:**

```bash
# Alle Container stoppen und entfernen (Daten bleiben in Docker-Volumes erhalten)
docker compose down
```

## GPU-Beschleunigung (AMD ROCm)

Für AMD-GPUs (z. B. den **Ryzen AI Max+ 395** / Strix Halo) nutzt du die ROCm-Compose-Datei — am einfachsten über den [Installer](#schnellstart-amd-rocm--empfohlen), oder manuell:

```bash
docker compose -f docker-compose.rocm.yml up -d
```

Der `ollama`-Dienst nutzt das offizielle `ollama/ollama:rocm`-Image und bekommt die GPU über `/dev/kfd` und `/dev/dri` durchgereicht.

**Voraussetzungen:**

- AMD-GPU mit geladenem `amdgpu`-Kernelmodul und installiertem **ROCm** (bzw. `amdgpu-dkms`)
- Die Geräte `/dev/kfd` und `/dev/dri/renderD*` müssen vorhanden sein
- Dein Benutzer muss in den Gruppen `video` und `render` sein (das Install-Skript erledigt das)

Beim **Ryzen AI Max+ 395** (iGPU `gfx1151`) setzt der Stack `HSA_OVERRIDE_GFX_VERSION=11.5.1`, falls ROCm die iGPU nicht direkt erkennt. Diesen Wert kannst du in der `.env` anpassen. Dank des großen Unified-Memory kann die iGPU sehr große Modelle laden.

> **Tipp:** Der [Installer](#schnellstart-amd-rocm--empfohlen) (`./install.sh`) prüft all das automatisch und meldet, was fehlt. Fehlt der Kernel-Treiber, **bietet er die Installation von `amdgpu-dkms` an** (nur der Kernel-Treiber — die ROCm-Bibliotheken bringt das Container-Image mit). Erzwingen mit `sudo ./install.sh --install-drivers`, überspringen mit `--skip-drivers`. Reiner Check ohne Änderungen: `./install.sh --check-only`.

> **Hinweis:** Nach einer frischen Treiber-Installation kann ein **Neustart** nötig sein, damit `/dev/kfd` erscheint. Danach den Installer einfach erneut ausführen. Passt die vorgeschlagene ROCm-Version nicht zu deiner Distribution, lässt sie sich per `ROCM_VERSION=6.x.y sudo ./install.sh --install-drivers` überschreiben.

## Leichtgewichtige Stacks

Du brauchst nicht den vollständigen Stack? Nutze eine vorkonfigurierte Teilmenge aus dem `stacks/`-Ordner:

> **Hinweis:** Die leichtgewichtigen Stacks teilen sich standardmäßig Container-Namen, Ports und Docker-Volume-Namen. Führe mit den Standard-Compose-Dateien immer nur eine Stack-Variante gleichzeitig aus; stoppe die aktuelle Variante, bevor du zu einer anderen wechselst. Um Funktionen zu kombinieren, nutze den vollständigen Stack oder passe Compose-Projektnamen, Container-Namen, Ports und Volumes an.

| Stack | Dienste | Speicher | Anwendungsfall |
|---|---|---|---|
| **[chat-ui](stacks/chat-ui/)** | Ollama + LiteLLM + AnythingLLM | ~5 GB | Web-basierte ChatGPT-ähnliche Chat-Oberfläche |
| **[voice-pipeline](stacks/voice-pipeline/)** | Whisper + Ollama + LiteLLM + Kokoro | ~6 GB | Sprache-zu-Text → LLM → Text-zu-Sprache |
| **[voice-chat](stacks/voice-chat/)** | Whisper + Ollama + LiteLLM + Kokoro + AnythingLLM | ~6,5 GB | Chat-UI mit Sprachein-/-ausgabe |
| **[rag-pipeline](stacks/rag-pipeline/)** | Ollama + LiteLLM + Embeddings | ~5 GB | Semantische Suche + LLM-Frage & Antwort |
| **[rag-pipeline-full](stacks/rag-pipeline-full/)** | Ollama + LiteLLM + Embeddings + Docling | ~6 GB | Dokumentenanalyse + semantische Suche + LLM-Frage & Antwort |
| **[code-assistant](stacks/code-assistant/)** | Ollama + LiteLLM + MCP Gateway + Embeddings | ~5 GB | KI-Programmierung mit Werkzeugen + semantische Codesuche |
| **[ai-tools](stacks/ai-tools/)** | Ollama + LiteLLM + MCP Gateway | ~5 GB | KI-Programmierassistent mit Werkzeugzugriff |
| **[chat-only](stacks/chat-only/)** | Ollama + LiteLLM | ~4,5 GB | Minimaler lokaler ChatGPT-Ersatz |

```bash
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack/stacks/chat-ui  # oder voice-pipeline, voice-chat, rag-pipeline, rag-pipeline-full, code-assistant, ai-tools, chat-only
docker compose up -d
```

## Architektur (CPU-/NVIDIA-Stack)

```mermaid
graph LR
    A["🎤 Audio-Eingabe"] -->|transkribieren| W["Whisper<br/>(Sprache-zu-Text)"]
    D["📄 Dokumente"] -->|parsen| DC["Docling<br/>(Dokument → Text)"]
    DC -->|einbetten| E["Embeddings<br/>(Text → Vektoren)"]
    E -->|speichern| VDB["pgvector<br/>(im gemeinsamen Postgres)"]
    W -->|Abfrage| E
    VDB -->|Kontext| L["LiteLLM<br/>(KI-Gateway)"]
    W -->|Text| L
    L -->|leitet weiter an| O["Ollama<br/>(lokales LLM)"]
    L -->|Antwort| T["Kokoro TTS<br/>(Text-zu-Sprache)"]
    T --> B["🔊 Audio-Ausgabe"]
    C["🤖 KI-Client<br/>(Cline, Claude usw.)"] -->|MCP-Werkzeuge| M["MCP Gateway<br/>(MCP-Endpunkt)"]
    C -->|Chat| L
    L -->|MCP-Protokoll| M
    U["👤 Benutzer"] -->|Chat| AN["AnythingLLM<br/>(Chat-UI)"]
    AN -->|LLM-Anfragen| L
    AN -->|MCP-Werkzeuge| M
    U -->|nutzen| C
    U -->|sprechen| A
    U -->|hochladen| D
```

**Hinweise:**

- Der Port von Ollama (`11434`) und der Port des MCP Gateway (`3000`) sind interne Ports des Docker-Netzwerks und werden standardmäßig nicht an den Host weitergegeben. Greife über LiteLLM auf Port `4000` auf dein LLM zu.
- Kokoro (TTS), Docling (Dokumentenanalyse) und WhisperLive (Echtzeit-STT) sind standardmäßig deaktiviert, um den Speicherverbrauch zu reduzieren. Kommentiere diese Dienste in `docker-compose.yml` aus, um sie zu aktivieren.

## Ausführung ohne Docker Compose

Wenn du lieber direkt `docker run`-Befehle verwendest, erstelle zunächst ein gemeinsames Netzwerk, damit die Dienste miteinander kommunizieren können:

```bash
docker network create ai-stack
```

Erzeuge dann ein PostgreSQL-Passwort und starte jeden Dienst im gemeinsamen Netzwerk:

> **Hinweis:** Warte bei manuellem `docker run`, bis jede Abhängigkeit bereit ist, bevor du Dienste startest, die sie nutzen (warte zum Beispiel auf PostgreSQL und weitere Abhängigkeiten wie Ollama oder MCP, bevor du LiteLLM startest; wenn du AnythingLLM nutzt, warte auf LiteLLM, bevor du es startest). Die folgenden Beispiele erzeugen eine PostgreSQL-Passwortvariable und verwenden sie für Postgres und LiteLLM wieder.

```bash
LITELLM_POSTGRES_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

# PostgreSQL mit pgvector (von LiteLLM benötigt; pgvector ermöglicht Vektorspeicherung für RAG)
docker run -d --name litellm-db --restart always \
    --network ai-stack \
    -e POSTGRES_USER=litellm \
    -e POSTGRES_PASSWORD="$LITELLM_POSTGRES_PASSWORD" \
    -e POSTGRES_DB=litellm \
    -v litellm-db:/var/lib/postgresql \
    pgvector/pgvector:pg18-trixie

# Ollama (LLM)
docker run -d --name ollama --restart always \
    --network ai-stack \
    -v ollama-data:/var/lib/ollama \
    -v ollama-shared:/var/lib/ollama-shared \
    hwdsl2/ollama-server

# MCP Gateway
docker run -d --name mcp --restart always \
    --network ai-stack \
    -v mcp-data:/var/lib/mcp \
    -v mcp-shared:/var/lib/mcp-shared \
    hwdsl2/mcp-gateway

# LiteLLM (KI-Gateway)
docker run -d --name litellm --restart always \
    --network ai-stack \
    -p 4000:4000 \
    -e LITELLM_OLLAMA_BASE_URL=http://ollama:11434 \
    -e LITELLM_MCP_URL=http://mcp:3000/mcp \
    -e LITELLM_DATABASE_URL="postgresql://litellm:${LITELLM_POSTGRES_PASSWORD}@litellm-db:5432/litellm" \
    -v litellm-data:/etc/litellm \
    -v ollama-shared:/var/lib/ollama-shared:ro \
    -v mcp-shared:/var/lib/mcp-shared:ro \
    -v litellm-shared:/var/lib/litellm-shared \
    hwdsl2/litellm-server

# Embeddings
docker run -d --name embeddings --restart always \
    --network ai-stack \
    -p 127.0.0.1:8000:8000 \
    -v embeddings-data:/var/lib/embeddings \
    hwdsl2/embeddings-server

# Whisper (STT)
docker run -d --name whisper --restart always \
    --network ai-stack \
    -p 127.0.0.1:9000:9000 \
    -v whisper-data:/var/lib/whisper \
    hwdsl2/whisper-server

# WhisperLive (Echtzeit-STT)
docker run -d --name whisper-live --restart always \
    --network ai-stack \
    -p 127.0.0.1:9090:9090 \
    -v whisper-live-data:/var/lib/whisper-live \
    hwdsl2/whisper-live-server

# AnythingLLM (Chat-UI)
docker run -d --name anythingllm --restart always \
    --network ai-stack \
    -p 3001:3001 \
    -e STORAGE_DIR=/app/server/storage \
    -e LLM_PROVIDER=generic-openai \
    -e GENERIC_OPEN_AI_BASE_PATH=http://litellm:4000/v1 \
    -e GENERIC_OPEN_AI_MODEL_PREF=ollama/llama3.2:3b \
    -e GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=131072 \
    -e ANYTHINGLLM_DEFAULT_CHAT_MODE=chat \
    -e EMBEDDING_ENGINE=native \
    -e DISABLE_TELEMETRY=true \
    -v anythingllm-data:/app/server/storage \
    -v litellm-shared:/var/lib/litellm-shared:ro \
    -v "$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro" \
    --entrypoint /bin/bash \
    mintplexlabs/anythingllm:1.15.0 \
    /usr/local/bin/chat-ui-bootstrap.sh

# Kokoro (TTS)
docker run -d --name kokoro --restart always \
    --network ai-stack \
    -p 127.0.0.1:8880:8880 \
    -v kokoro-data:/var/lib/kokoro \
    hwdsl2/kokoro-server

# Docling (Dokumentenanalyse)
docker run -d --name docling --restart always \
    --network ai-stack \
    -p 127.0.0.1:5001:5001 \
    -v docling-data:/var/lib/docling \
    hwdsl2/docling-server
```

**Hinweis:** Das gemeinsame Netzwerk erlaubt es den Diensten, sich gegenseitig über den Container-Namen zu erreichen (z. B. verbindet sich LiteLLM über `http://ollama:11434` mit Ollama). Du kannst nur die Dienste starten, die du benötigst — sie müssen nicht alle zusammen laufen.

**Ein Modell herunterladen** (erforderlich, bevor LLM-Anfragen gestellt werden):

```bash
docker exec ollama ollama_manage --pull llama3.2:3b
```

## Podman verwenden

Der Stack läuft nach bestem Bemühen unter [Podman](https://podman.io/). Die CPU-Compose-Dateien funktionieren unverändert; GPU-Beschleunigung und Hosts mit aktiviertem SELinux benötigen einige zusätzliche Schritte, die unten beschrieben werden. Podman **4.1+** wird empfohlen.

**1. Installiere den Docker-CLI-Shim.** Damit die `docker`-Befehle in dieser README und der `stack-check.sh`-Health-Check unverändert funktionieren, installiere das Paket `podman-docker` (stellt einen `docker` → `podman`-Wrapper bereit):

```bash
# Fedora / RHEL / CentOS Stream
sudo dnf install -y podman-docker

# Debian / Ubuntu
sudo apt-get install -y podman-docker
```

> **Hinweis:** Ein Shell-`alias docker=podman` ist **nicht** ausreichend — Aliase werden von Skripten wie `stack-check.sh` nicht erkannt. Nutze stattdessen das Paket `podman-docker` (oder einen `docker` → `podman`-Symlink in deinem `PATH`). Alternativ erkennt `stack-check.sh` Podman automatisch; du kannst es auch mit `CONTAINER_ENGINE=podman ./stack-check.sh` erzwingen.

**2. Installiere einen Compose-Provider.** `podman compose` delegiert an einen externen Provider. Installiere entweder `podman-compose` oder `docker-compose`:

```bash
# Fedora / RHEL / CentOS Stream
sudo dnf install -y podman-compose

# Debian / Ubuntu
sudo apt-get install -y podman-compose
```

**3. Starte den Stack.** Mit installiertem Shim funktioniert jeder Befehl in dieser README unverändert. Ohne ihn ersetze `docker` durch `podman`:

```bash
git clone https://github.com/hwdsl2/self-hosted-ai-stack
cd self-hosted-ai-stack
podman compose up -d
```

Führe den Health-Check aus (erkennt die Engine automatisch):

```bash
./stack-check.sh
```

**GPU-Beschleunigung (CDI).** Podman liest den Compose-`deploy.resources`-GPU-Block nicht. Nutze stattdessen das [Container Device Interface (CDI)](https://github.com/cncf-tags/container-device-interface). Erzeuge nach der Installation des [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) eine CDI-Spezifikation:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Stelle dann die GPU den relevanten Diensten zur Verfügung. Ersetze für `podman compose` den `deploy:`-Block in `docker-compose.cuda.yml` durch einen `devices:`-Eintrag für die Dienste `ollama` (und `whisper`):

```yaml
    devices:
      - nvidia.com/gpu=all
```

Für einen einfachen `podman run`-Befehl füge `--device nvidia.com/gpu=all` hinzu.

**SELinux.** Auf Hosts mit aktiviertem SELinux (Fedora, RHEL, CentOS Stream) benötigen per Bind eingebundene Dateien einen Relabel-Suffix, sonst wird dem Container der Zugriff verweigert. Füge `:z` (gemeinsam) zum `chat-ui-bootstrap.sh`-Bind-Mount hinzu:

- In `docker-compose.yml`: Ändere `./chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro` zu `./chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro,z`
- Im obigen `podman run`-Befehl: Ändere `"$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro"` zu `"$(pwd)/chat-ui-bootstrap.sh:/usr/local/bin/chat-ui-bootstrap.sh:ro,z"`

Benannte Volumes benötigen kein Relabeling.

**Nächste Schritte:** Lade ein Modell herunter und greife auf die Dienste zu — folge den Anweisungen im [Schnellstart](#schnellstart) ab „Ein Modell herunterladen". Mit installiertem `podman-docker`-Shim funktionieren alle Befehle unverändert.

## MCP Gateway mit LiteLLM verbinden

LiteLLM und MCP Gateway werden bei Verwendung der Compose-Dateien in diesem Repository **automatisch verbunden** — es ist keine manuelle Schlüsseleinrichtung nötig.

API-Schlüssel werden automatisch über gemeinsame Docker-Volumes zwischen den Diensten geteilt:

- Ollama erzeugt beim ersten Start einen API-Schlüssel und kopiert ihn in ein gemeinsames Volume
- MCP Gateway macht dasselbe
- LiteLLM liest beim Start beide Schlüssel aus den gemeinsamen Volumes

Die Umgebungsvariablen `LITELLM_MCP_URL=http://mcp:3000/mcp` und `LITELLM_OLLAMA_BASE_URL=http://ollama:11434` sind in den Compose-Dateien vorkonfiguriert, sodass alle Dienste mit einem einzigen `docker compose up -d` automatisch verbunden werden.

Einmal verbunden, können KI-Clients, die LiteLLM aufrufen, MCP-Werkzeuge (Dateisystem, Fetch, GitHub usw.) direkt über den LiteLLM-Proxy nutzen.

## Beispiel für eine Sprach-Pipeline

Transkribiere eine gesprochene Frage, erhalte über Ollama eine lokale LLM-Antwort und wandle sie in Sprache um:

**Hinweis:** Kokoro (TTS) ist standardmäßig deaktiviert. Um dieses Beispiel zu nutzen, kommentiere zunächst den `kokoro`-Dienst in `docker-compose.yml` aus und führe dann `docker compose up -d` aus.

**Tipp:** Brauchst du eine Beispiel-Audiodatei? Lade dieses englische Sprachbeispiel (WAV, MIT-Lizenz) aus dem [Azure Samples](https://github.com/Azure-Samples/cognitive-services-speech-sdk)-Repository herunter:

```bash
curl -L -o sample_speech.wav \
    "https://github.com/Azure-Samples/cognitive-services-speech-sdk/raw/master/sampledata/audiofiles/katiesteve.wav"
```

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)
WHISPER_KEY=$(docker exec whisper whisper_manage --getkey)
KOKORO_KEY=$(docker exec kokoro kokoro_manage --getkey)

# Schritt 1: Audio in Text transkribieren (Whisper)
TEXT=$(curl -s http://localhost:9000/v1/audio/transcriptions \
    -H "Authorization: Bearer $WHISPER_KEY" \
    -F file=@sample_speech.wav -F model=whisper-1 | jq -r .text)

# Schritt 2: Text über LiteLLM an Ollama senden und eine Antwort erhalten
RESPONSE=$(curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"ollama/llama3.2:3b\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEXT\"}]}" \
    | jq -r '.choices[0].message.content')

# Schritt 3: Die Antwort in Sprache umwandeln (Kokoro TTS)
curl -s http://localhost:8880/v1/audio/speech \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $KOKORO_KEY" \
    -d "{\"model\":\"tts-1\",\"input\":\"$RESPONSE\",\"voice\":\"af_heart\"}" \
    --output response.mp3
```

## Vektordatenbank

Das PostgreSQL des Stacks wird mit der [pgvector](https://github.com/pgvector/pgvector)-Erweiterung ausgeliefert, sodass du Embeddings in derselben Datenbank speichern und abfragen kannst, die auch LiteLLM verwendet — es ist keine separate Vektordatenbank erforderlich.

Aktiviere die Erweiterung einmalig (die Datenbank bleibt bestehen, dies muss also nur ein einziges Mal getan werden):

```bash
docker exec litellm-db psql -U litellm -d litellm -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```

Überprüfe, ob sie aktiviert ist:

```bash
docker exec litellm-db psql -U litellm -d litellm -c "SELECT extname, extversion FROM pg_extension WHERE extname='vector';"
```

Du kannst dann eine Tabelle mit einer `vector`-Spalte erstellen (nutze die Dimension deines Embedding-Modells — z. B. `384` für das Standardmodell `BAAI/bge-small-en-v1.5`) und mit dem `<=>`-Operator eine Ähnlichkeitssuche durchführen. Für größere oder hybride Suchen kannst du stattdessen eine dedizierte Vektordatenbank wie Qdrant oder Chroma betreiben.

## Beispiel für eine RAG-Pipeline

Bette Dokumente für die semantische Suche ein, rufe Kontext ab und beantworte dann Fragen mit einem lokalen Ollama-Modell:

```bash
LITELLM_KEY=$(docker exec litellm litellm_manage --getkey)
EMBED_KEY=$(docker exec embeddings embed_manage --getkey)

# Schritt 1: Einen Dokumentabschnitt einbetten und den Vektor in deiner Vektor-DB speichern
curl -s http://localhost:8000/v1/embeddings \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $EMBED_KEY" \
    -d '{"input": "Docker simplifies deployment by packaging apps in containers.", "model": "text-embedding-ada-002"}' \
    | jq '.data[0].embedding'
# → Speichere den zurückgegebenen Vektor zusammen mit dem Quelltext in pgvector (im Postgres des Stacks enthalten) oder einer anderen Vektor-DB wie Qdrant oder Chroma.

# Schritt 2: Bette zur Abfragezeit die Frage ein, rufe die am besten passenden Abschnitte aus
#          der Vektor-DB ab und sende dann die Frage und den abgerufenen Kontext über LiteLLM an Ollama.
curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "ollama/llama3.2:3b",
      "messages": [
        {"role": "system", "content": "Answer using only the provided context."},
        {"role": "user", "content": "What does Docker do?\n\nContext: Docker simplifies deployment by packaging apps in containers."}
      ]
    }' \
    | jq -r '.choices[0].message.content'
```

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

## Nutzungszählungen

Self-Hosted AI Stack nutzt anonyme, aggregierte Zählungen der Downloads von GitHub-Release-Assets, um die Nutzung zu verstehen und zukünftige Verbesserungen zu priorisieren. Es wird keine Telemetrie-Nutzlast gesendet und kein privater Collector verwendet.

Um die Nutzungszählungen beim Start des Stacks zu deaktivieren:

```bash
AI_STACK_DISABLE_USAGE_COUNTS=1 docker compose up -d
```

## Anpassung

Jeder Dienst kann über eine optionale env-Datei konfiguriert werden. Kopiere die Beispiel-env-Datei aus dem jeweiligen Repository, bearbeite sie und kommentiere den Volume-Mount in `docker-compose.yml` aus:

| Dienst | Env-Datei | Repository |
|---|---|---|
| Ollama | `ollama.env` | [docker-ollama](https://github.com/hwdsl2/docker-ollama) |
| LiteLLM | `litellm.env` | [docker-litellm](https://github.com/hwdsl2/docker-litellm) |
| Embeddings | `embed.env` | [docker-embeddings](https://github.com/hwdsl2/docker-embeddings) |
| Whisper | `whisper.env` | [docker-whisper](https://github.com/hwdsl2/docker-whisper) |
| WhisperLive | `whisper-live.env` | [docker-whisper-live](https://github.com/hwdsl2/docker-whisper-live) |
| Kokoro | `kokoro.env` | [docker-kokoro](https://github.com/hwdsl2/docker-kokoro) |
| MCP Gateway | `mcp.env` | [docker-mcp-gateway](https://github.com/hwdsl2/docker-mcp-gateway) |
| Docling | `docling.env` | [docker-docling](https://github.com/hwdsl2/docker-docling) |

AnythingLLM wird über seine Web-UI unter `http://<server-ip>:3001` konfiguriert. Du kannst den LLM-Anbieter, das Modell, die Embedding-Engine und andere Einstellungen unter **Settings** ändern. Weitere Details findest du in der [AnythingLLM-Dokumentation](https://docs.useanything.com/).

**Den Embeddings-Dienst des Stacks nutzen (optional).** Standardmäßig bettet AnythingLLM Dokumente prozessintern mit seinem mitgelieferten MiniLM-Modell ein und speichert die Vektoren in seiner eigenen LanceDB. Um stattdessen den [Embeddings](https://github.com/hwdsl2/docker-embeddings)-Dienst des Stacks (BAAI/bge-small-en-v1.5) und/oder das pgvector-fähige Postgres des Stacks zu nutzen, bearbeite den `anythingllm`-Dienst in `docker-compose.yml`: Kommentiere `EMBEDDING_ENGINE=native` aus und den darunterliegenden Opt-in-Block ein. Kommentiere außerdem den `depends_on`-Hinweis aus, damit die Embeddings-/DB-Dienste zuerst starten. Wenn `VECTOR_DB=pgvector` aktiviert ist und kein `PGVECTOR_CONNECTION_STRING` gesetzt ist, nutzt AnythingLLM automatisch das erzeugte Postgres-Passwort aus `ai-stack-shared`. AnythingLLM erstellt bei der ersten Nutzung automatisch die `vector`-Erweiterung und die Tabelle `anythingllm_vectors`. ⚠️ Das Umstellen des Embedders oder Vektorspeichers bei einer bestehenden Bereitstellung macht zuvor eingebettete Dokumente inkompatibel — bette deine Workspaces nach der Änderung erneut ein.

Detaillierte Konfigurationsoptionen, API-Referenz und Modellverwaltung findest du in der Dokumentation im Repository jedes Dienstes.

## Ins Internet gerichtete Bereitstellungen

Standardmäßig lauschen alle Dienste über einfaches HTTP. Für ins Internet gerichtete Bereitstellungen nutze das mitgelieferte Caddy-Overlay, um automatisches HTTPS hinzuzufügen. Im Proxy-Modus ist Caddy der einzige öffentliche Listener auf den Ports `80` und `443`; die direkten AnythingLLM- und LiteLLM-Ports werden auf `127.0.0.1` neu gebunden.

Voraussetzungen:

- Docker Compose `2.24.4+` (erforderlich für die Port-Überschreibung des Proxy-Overlays)
- Ein DNS-`A`/`AAAA`-Eintrag für deine Domain, der auf diesen Server zeigt
- Eingehende `80/tcp`, `443/tcp` und idealerweise `443/udp` in deiner Firewall/Sicherheitsgruppe geöffnet
- Kein anderer Dienst nutzt bereits die Ports `80` oder `443` auf dem Host

**CPU-Stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

**CUDA-Stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.cuda.yml -f docker-compose.proxy.yml up -d
```

Öffne `https://chat.example.com` (ersetze durch deine `DOMAIN`), um auf AnythingLLM zuzugreifen. Im Proxy-Modus bleiben `http://127.0.0.1:3001` und `http://127.0.0.1:4000/ui` auf dem Host verfügbar, aber die direkten Ports `3001` und `4000` sind von außerhalb des Servers nicht erreichbar.

Die Standard-Compose-Dateien veröffentlichen LiteLLM auf Port `4000`. Das Proxy-Overlay ändert diesen direkten Port auf localhost-only, und die mitgelieferte Caddyfile leitet standardmäßig nur AnythingLLM weiter. Das Auskommentieren des optionalen LiteLLM-Hostname-Blocks stellt LiteLLM über Caddy bereit, halte daher den LiteLLM-Masterschlüssel geheim.

Fehlerbehebung:

```bash
docker logs ai-stack-caddy
# Nutze dieselben -f-Dateien, mit denen du den Stack gestartet hast
docker compose -f docker-compose.yml -f docker-compose.proxy.yml ps
```

Wenn Caddy eine unbekannte `request_body`-Direktive meldet, lade das aktuelle `caddy:2`-Image herunter und starte das Overlay neu.

Für ältere Docker-Compose-Versionen oder Podman nutze stattdessen einen host-basierten Reverse-Proxy: Binde die direkten HTTP-Ports in der Compose-Datei an localhost (zum Beispiel `"127.0.0.1:3001:3001/tcp"` und `"127.0.0.1:4000:4000/tcp"`) und leite an diese localhost-Ports weiter. Für stack-spezifische Caddy- und nginx-Beispiele siehe den [Abschnitt zum manuellen Reverse-Proxy für die Chat-UI](stacks/chat-ui/#manual-reverse-proxy).

Wenn du Dienste ins Internet stellst, nutze wo vorhanden die erzeugten API-Schlüssel. Setze für bestehende Bereitstellungen ohne Schlüssel die API-Schlüssel über die entsprechenden env-Dateien, bevor du diese Dienste veröffentlichst.

## Sicherung und Wiederherstellung

Deine API-Schlüssel, Modelle und Konfiguration werden in Docker-Volumes gespeichert. Sichere sie vor einem Upgrade oder vor Änderungen:

```bash
# API-Schlüssel exportieren (während die Container laufen)
docker exec ollama ollama_manage --getkey
docker exec litellm litellm_manage --getkey
docker exec mcp mcp_manage --getkey
# Optionale Dienste; ignoriert, wenn der Container nicht aktiviert/laufend ist
docker exec whisper whisper_manage --getkey 2>/dev/null || true
docker exec whisper-live whisper_live_manage --getkey 2>/dev/null || true
docker exec kokoro kokoro_manage --getkey 2>/dev/null || true
docker exec embeddings embed_manage --getkey 2>/dev/null || true
docker exec docling docling_manage --getkey 2>/dev/null || true

# Alle Volumes sichern (stoppe zuerst die Dienste)
# Alle Container stoppen und entfernen (Daten bleiben in Docker-Volumes erhalten)
docker compose down
mkdir -p backups
for vol in ollama-data litellm-data litellm-db ai-stack-shared embeddings-data whisper-data whisper-live-data kokoro-data mcp-data docling-data anythingllm-data caddy-data caddy-config; do
  docker volume inspect "$vol" >/dev/null 2>&1 && \
    docker run --rm -v "${vol}:/source:ro" -v "$(pwd)/backups:/backup" \
      alpine tar czf "/backup/${vol}.tar.gz" -C /source .
done
```

**Hinweis:** Sichere `ai-stack-shared` zusammen mit `litellm-db`; neue Installationen speichern dort das erzeugte PostgreSQL-Passwort. Die Volumes `ollama-shared`, `mcp-shared` und `litellm-shared` sind kurzlebige Volumes zum Teilen von Schlüsseln und müssen nicht gesichert werden.

Anweisungen zur Wiederherstellung, Server-Migration und die vollständige Checkliste vor dem Upgrade findest du in der Anleitung zu [Sicherung und Wiederherstellung](docs/backup-restore.md).

## PostgreSQL-Zugangsdaten

Neue Docker-Compose-Installationen erzeugen automatisch ein zufälliges PostgreSQL-Passwort und speichern es im `ai-stack-shared`-Volume. Bestehende Standardinstallationen nutzen aus Kompatibilitätsgründen weiterhin das ältere `litellm`-Datenbankpasswort.

Wenn du das Datenbankpasswort zuvor angepasst hast, setze `LITELLM_POSTGRES_PASSWORD` in deiner Shell-Umgebung auf dieses aktuelle Passwort, bevor du `docker compose up -d` ausführst, oder behalte eine explizite `LITELLM_DATABASE_URL`-Überschreibung in `litellm.env`.

## Images aktualisieren

Um alle Dienste auf die neuesten Versionen zu aktualisieren:

```bash
git pull
docker compose pull
docker compose up -d
./stack-check.sh
```

Führe nach dem Neustart des Stacks `./stack-check.sh` aus, um zu bestätigen, dass die Dienste und die erzeugte Verdrahtung der Zugangsdaten fehlerfrei sind.

`git pull` aktualisiert alle Projektdateien (einschließlich etwaiger Änderungen an den Compose-Dateien); `docker compose pull` aktualisiert die Dienst-Images. Wenn du `docker-compose.yml` angepasst hast, führt `git pull` Änderungen automatisch zusammen oder fordert dich auf, Konflikte in denselben Zeilen aufzulösen.

**Einmaliger Hinweis für ältere Installationen:** Wenn du ein AnythingLLM-Passwort vor dem `.env`-Persistenz-Fix gesetzt hast, kann die erste Neuerstellung des Containers nach dem Upgrade dieses Passwort löschen und AnythingLLM ungeschützt lassen. Öffne AnythingLLM nach dem Update sofort und bestätige, dass der Passwortschutz noch aktiviert ist. Falls nicht, setze ein neues Passwort unter **Settings → Security**. Zukünftige Container-Neuerstellungen bewahren es.

AnythingLLM ist auf ein stabiles Release-Tag statt auf `latest` gepinnt, weil das Upstream-`latest`-Image dem Master-Branch folgt. Wenn ein neueres AnythingLLM-Release verfügbar ist, sichere zuerst, aktualisiere das Tag in den Compose-Dateien und führe dann die obigen Befehle aus.

Deine Daten bleiben in den Docker-Volumes erhalten. **[Sichere](#sicherung-und-wiederherstellung) immer, bevor du ein Upgrade durchführst.**

## Lizenz

Copyright (C) 2026 Lin Song   
Dieses Werk ist unter der [MIT-Lizenz](https://opensource.org/licenses/MIT) lizenziert.

Dieses Projekt ist eine unabhängige Docker-Konfiguration und ist nicht mit Docker, Inc., Ollama, Berri AI (LiteLLM), Hugging Face, hexgrad (Kokoro), OpenAI, SYSTRAN oder MCPHub verbunden, wird von ihnen nicht unterstützt oder gesponsert. Docker ist eine Marke oder eingetragene Marke von Docker, Inc.
