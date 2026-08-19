# Installation & Erste Schritte

Voraussetzungen, Installer, GPU-Einrichtung und Deinstallation.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/installation.md)

**Dokumentation:** **Installation & Erste Schritte** · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Schnellstart (AMD ROCm) — empfohlen

Diese Variante ist komplett auf **Upstream-Images** umgebaut und für **AMD-GPUs** ausgelegt (getestet für den **Ryzen AI Max+ 395** / Strix Halo). Sie nutzt:

- **[Ollama (ROCm)](https://hub.docker.com/r/ollama/ollama)** als LLM-Engine mit AMD-GPU-Beschleunigung
- **[Open WebUI](https://github.com/open-webui/open-webui)** als Chat-Oberfläche (ersetzt AnythingLLM)
- **[LiteLLM](https://github.com/BerriAI/litellm)** als AI-Gateway, **MCP Gateway** + **Code-Sandbox** (Werkzeuge, inkl. `run_python`/`run_shell` zum Selbsttesten), **PostgreSQL/pgvector**, **Whisper** (STT) und **Embeddings** (TEI)
- ein **[modernes Status-Dashboard](architektur.md#dashboard)**, das den Live-Status aller Dienste zeigt

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

## GPU-Beschleunigung (AMD ROCm)

Für AMD-GPUs (z. B. den **Ryzen AI Max+ 395** / Strix Halo) nutzt du die ROCm-Compose-Datei — am einfachsten über den **Installer**, oder manuell:

```bash
docker compose -f docker-compose.rocm.yml up -d --build
```

Der `ollama`-Dienst nutzt das offizielle `ollama/ollama:rocm`-Image und bekommt die GPU über `/dev/kfd` und `/dev/dri` durchgereicht. `--build` sorgt dafür, dass der lokal gebaute `sandbox-mcp`-Dienst (Code-Sandbox) korrekt gebaut statt fälschlich von einer Registry gezogen wird.

**Voraussetzungen:**

- AMD-GPU mit geladenem `amdgpu`-Kernelmodul und installiertem **ROCm** (bzw. `amdgpu-dkms`)
- Die Geräte `/dev/kfd` und `/dev/dri/renderD*` müssen vorhanden sein
- Dein Benutzer muss in den Gruppen `video` und `render` sein (das Install-Skript erledigt das)

Beim **Ryzen AI Max+ 395** (iGPU `gfx1151`) setzt der Stack `HSA_OVERRIDE_GFX_VERSION=11.5.1`, falls ROCm die iGPU nicht direkt erkennt. Diesen Wert kannst du in der `.env` anpassen. Dank des großen Unified-Memory kann die iGPU sehr große Modelle laden.

> **Tipp:** Der **Installer** (`./install.sh`) prüft all das automatisch und meldet, was fehlt. Fehlt der Kernel-Treiber, **bietet er die Installation von `amdgpu-dkms` an** (nur der Kernel-Treiber — die ROCm-Bibliotheken bringt das Container-Image mit). Erzwingen mit `sudo ./install.sh --install-drivers`, überspringen mit `--skip-drivers`. Reiner Check ohne Änderungen: `./install.sh --check-only`.

> **Hinweis:** Nach einer frischen Treiber-Installation kann ein **Neustart** nötig sein, damit `/dev/kfd` erscheint. Danach den Installer einfach erneut ausführen. Passt die vorgeschlagene ROCm-Version nicht zu deiner Distribution, lässt sie sich per `ROCM_VERSION=6.x.y sudo ./install.sh --install-drivers` überschreiben.

## Deinstallieren

Das Install-Skript kann auch aufräumen — sowohl den neuen ROCm-Stack als auch den **alten** Stack (AnythingLLM/`hwdsl2`-Images):

```bash
sudo ./install.sh --uninstall   # Container & Netzwerke entfernen, Daten (Volumes) behalten
sudo ./install.sh --purge       # ALLES entfernen: auch Modelle, Chats, Datenbank und .env
```

`--purge` ist unwiderruflich und fragt vorher zur Sicherheit nach (Bestätigung mit »loeschen«; mit `-y` überspringst du die Rückfrage). Firewall-Regeln bleiben unberührt.

> Die folgenden Abschnitte beschreiben den **ursprünglichen CPU-/NVIDIA-Stack** (mit den `hwdsl2/*`-Images und AnythingLLM). Für AMD nutzt du den ROCm-Schnellstart oben.
