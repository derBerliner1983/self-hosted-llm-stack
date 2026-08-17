# Open Interpreter (CLI)

Assistent für die Kommandozeile: Aufgabe beschreiben, das Modell schreibt Code und führt ihn aus.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/open-interpreter.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · **Open Interpreter (CLI)** · [Android-Entwicklung](android.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Was das ist — und was es nicht ist

[Open Interpreter](https://github.com/OpenInterpreter/open-interpreter) ist ein Assistent für die **Kommandozeile**, keine Weboberfläche. Du beschreibst eine Aufgabe, das Modell schreibt Code (Python, Shell, JavaScript …), führt ihn aus, sieht das Ergebnis und arbeitet weiter — so lange, bis die Aufgabe erledigt ist.

Der Unterschied zur [Code-Sandbox](code-sandbox.md): Die Sandbox ist ein **Werkzeug fürs Chat-Modell** — du redest mit Open WebUI oder LibreChat, und das Modell benutzt die Sandbox nebenbei. Open Interpreter ist umgekehrt das **Hauptprogramm**: du sitzt direkt davor, im Terminal, ohne Chat-Oberfläche dazwischen.

Es nutzt dasselbe LiteLLM wie alles andere — also dein lokales Modell, keine Cloud.

## Installieren

Beim Installer wird gefragt:

```
Open Interpreter — Kommandozeilen-Assistent: du beschreibst eine
Aufgabe, das Modell schreibt Code und führt ihn aus. Läuft im Container
(sieht nur den Arbeitsbereich /work) und nutzt dein lokales LiteLLM.
Kein Dienst — wird nur auf Zuruf gestartet: ./scripts/interpreter.sh

Open Interpreter mitinstallieren? [j/N]
```

Die Antwort landet als `INSTALL_OPEN_INTERPRETER` in der `.env`; beim nächsten Lauf wird nicht erneut gefragt. Ohne Rückfrage geht es auch:

```bash
./install.sh --with-interpreter      # mitinstallieren
./install.sh --without-interpreter   # überspringen
```

Nachträglich nachrüsten — im [Kontrollzentrum](kontrollzentrum.md) unter **CLI-Werkzeuge → Open Interpreter → Installieren**, oder direkt:

```bash
./scripts/interpreter.sh --build
```

## Starten

```bash
./scripts/interpreter.sh                          # interaktive Sitzung
./scripts/interpreter.sh --model ollama/qwen2.5:14b
./scripts/interpreter.sh -y                       # ohne Rückfrage vor jedem Schritt
```

Alle weiteren Argumente reicht das Skript unverändert an Open Interpreter durch.

Beim ersten Start wird das Image gebaut (ein paar Minuten). Läuft LiteLLM gerade nicht, startet das Skript es mit — sonst würde Open Interpreter erst beim ersten Prompt mit einer Verbindungsmeldung scheitern, die niemand zuordnen kann.

## Warum im Container

Open Interpreter führt aus, was das Modell schreibt. Auf dem Host hieße das: Zugriff auf alles, was dein Benutzer darf — inklusive deiner Wissensdatenbank und deiner Konfiguration.

Deshalb läuft es hier **im Container** und sieht nur `/work`:

- Der Arbeitsbereich `/work` ist dasselbe Volume (`sandbox-work`) wie bei der [Code-Sandbox](code-sandbox.md). Was das Chat-Modell dort angelegt hat, findest du hier wieder — und umgekehrt.
- Alles andere auf deinem Rechner ist für Open Interpreter schlicht nicht vorhanden. Der Vault insbesondere **nicht**.
- Ein `docker rmi` entfernt es rückstandslos, statt hunderte Python-Pakete im System zu hinterlassen.

Wer mehr Zugriff braucht, hängt ihn gezielt an — in `docker-compose.rocm.yml` beim Dienst `interpreter`:

```yaml
    volumes:
      - sandbox-work:/work
      - ${VAULT_HOST_PATH:-./vault}:/vault:ro   # Vault NUR lesend
```

> Den Vault, wenn überhaupt, **nur mit `:ro`** einhängen. Schreibzugriff durch ein Werkzeug, das eigenständig Code ausführt, ist genau der Weg, auf dem eine Wissensdatenbank still zumüllt.

## Einstellungen

Alles über die `.env`:

| Variable | Standard | Bedeutung |
|---|---|---|
| `INSTALL_OPEN_INTERPRETER` | Abfrage | `yes` / `no` — merkt deine Auswahl |
| `INTERPRETER_MODEL` | `ollama/gemma3:12b` | Modellname **wie bei LiteLLM registriert** |
| `INTERPRETER_CONTEXT_WINDOW` | `16384` | Kontextfenster |
| `INTERPRETER_MAX_TOKENS` | `4096` | maximale Antwortlänge |
| `INTERPRETER_API_BASE` | `http://litellm:4000/v1` | Endpunkt |
| `OPEN_INTERPRETER_VERSION` | `0.4.3` | Paketversion im Image |

Welche Modellnamen es bei dir gibt, zeigt:

```bash
docker exec litellm curl -s http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | grep -o '"id":"[^"]*"'
```

> **Zum Präfix:** LiteLLM kennt die Modelle als `ollama/<name>`. Open Interpreter benutzt intern die litellm-Bibliothek, und die braucht ein vorangestelltes `openai/`, damit sie den LiteLLM-Proxy als OpenAI-kompatiblen Endpunkt anspricht statt selbst Ollama zu erraten. Aus `ollama/gemma3:12b` wird also `openai/ollama/gemma3:12b` — **das setzt der Container selbst**, in die `.env` gehört der kurze Name.

## Grenzen

- **Das Netzwerk ist nicht eingeschränkt** — der Container hängt im Docker-Netz des Stacks und kommt damit auch ins Internet. Wenn du das nicht willst, `network_mode: none` beim Dienst setzen; dann ist allerdings auch LiteLLM unerreichbar.
- **Kleinere Modelle scheitern hier häufiger** als im Chat: Open Interpreter verlangt sauberes, mehrstufiges Werkzeug-Verhalten. Wenn es im Kreis läuft, hilft ein größeres Modell mehr als ein besserer Prompt.
- **`-y` heißt wirklich ohne Rückfrage.** Im Container ist der Schaden auf `/work` begrenzt — genau deshalb steht es hier so.

## Entfernen

Im [Kontrollzentrum](kontrollzentrum.md): **Open Interpreter → Entfernen**. Oder:

```bash
docker compose -f docker-compose.rocm.yml --profile cli down --rmi local interpreter
```

`/work` bleibt dabei erhalten — das Volume gehört auch der Code-Sandbox.
