# Code-Sandbox

Code ausführen und testen lassen — Isolation, Arbeitsbereich und weitere Sprachen.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/code-sandbox.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · **Code-Sandbox** · [Android-Entwicklung](android.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Code-Sandbox (`run_python` / `run_shell` fürs LLM)

Zusätzlich zu MCP Gateway bringt der Stack eine eigene **Code-Sandbox** mit (`sandbox-mcp/`), damit das Modell selbst geschriebenen Code **testen, Fehler erkennen und iterativ korrigieren** kann, statt ungetesteten Code auszugeben. Drei Werkzeuge, über denselben LiteLLM-MCP-Mechanismus bereitgestellt:

- `run_python(code)` — führt Python-Code aus
- `run_shell(command)` — führt einen Shell-Befehl aus (**bash**, nicht `sh` — Modelle schreiben fast immer Bash-Syntax)
- `run_script(script, interpreter, args)` — führt ein **komplettes, mehrzeiliges Skript** aus: bash, sh, python3, node, ruby, perl, php oder pwsh, wahlweise mit Argumenten

> **Warum `run_script` zusätzlich zu `run_shell`?** Ein ganzes Skript in einen Einzeiler zu quetschen scheitert regelmäßig an Anführungszeichen und Zeilenumbrüchen — genau daran verheddern sich Modelle und probieren dann dutzende Varianten. `run_script` nimmt den Inhalt unverändert entgegen (intern base64-kodiert übertragen, damit Quotes, `$`, Backslashes und Umlaute garantiert heil ankommen), legt ihn als Datei ab und ruft den gewünschten Interpreter darauf auf.

> ⚠️ **Kein Terminal in der Sandbox:** `tput cols`/`tput lines` liefern dort keine echten Werte, und Farb-Escapes erscheinen in der Ausgabe als Rohtext. Beides ist normal und sagt nichts darüber aus, wie sich das Skript im Terminal des Nutzers verhält — Skripte sollten für `tput` einen Rückfallwert vorsehen (`$(tput cols 2>/dev/null || echo 80)`).

**Wie die Isolation funktioniert:** Jeder einzelne Aufruf startet einen **komplett neuen, isolierten Wegwerf-Container** — kein Netzwerkzugriff, schreibgeschütztes Dateisystem, Speicher-/CPU-/Prozess-Limits, kein root, alle Linux-Capabilities entfernt, Zeitlimit (Standard 15 s, maximal 60 s). Nach jedem Lauf wird der Container sofort gelöscht.

**Zwei Schreibbereiche — der Unterschied ist wichtig:**

| Pfad | Verhalten | wofür |
|---|---|---|
| **`/work`** | **bleibt zwischen Aufrufen erhalten** (eigenes Docker-Volume `sandbox-work`), ist das Startverzeichnis | Testdateien anlegen und im nächsten Aufruf dagegen testen, Skripte iterativ verbessern |
| `/tmp` | wird bei jedem Aufruf geleert | Wegwerf-Zwischenstände |

> **Warum `/work` überhaupt existiert:** Ohne persistenten Bereich ist mehrschrittige Arbeit unmöglich — ein Modell, das Testverzeichnisse anlegt und im nächsten Aufruf dagegen testen will, findet sie schlicht nicht mehr und dreht sich im Kreis (im Betrieb genau so beobachtet). Aufgaben der Form „schreib ein Skript **und teste es**" gehen erst damit.

> ⚠️ **Sicherheitliche Einordnung:** `/work` überdauert bewusst die Aufrufe — Code aus einem Aufruf kann also Dateien für spätere Aufrufe hinterlassen. Gegenüber dem Host und dem restlichen Stack bleibt die Isolation unverändert (kein Netz, kein root, kein Zugriff auf Vault oder andere Volumes). Wer den Bereich leeren will: `docker volume rm sandbox-work` (Dienst vorher stoppen).

> ⚠️ **Sicherheitshinweis:** Damit der Sandbox-Dienst pro Aufruf einen frischen Container starten kann, braucht er Zugriff auf den **Docker-Socket** des Hosts (`/var/run/docker.sock`). Das ist mächtig — wer diesen internen Dienst erreichen kann, kann im Prinzip beliebige Container auf dem Host starten. Der Dienst ist deshalb bewusst **nur intern** im Docker-Netz erreichbar, ohne Port nach außen. Für ein Einzelnutzer-Setup im eigenen LAN ist das ein vertretbarer Kompromiss; falls du diese Fähigkeit nicht willst, entferne einfach den `sandbox-mcp`-Dienst (und den zugehörigen `code_sandbox`-Eintrag in `litellm/config.yaml`) und starte den Stack neu.

Konfigurierbar über `.env`: `SANDBOX_IMAGE` (Basis-Image der Sandbox, Standard `python:3.12-slim`), `SANDBOX_DEFAULT_TIMEOUT`, `SANDBOX_MAX_TIMEOUT`, `SANDBOX_MEM_LIMIT`, `SANDBOX_TMPFS_SIZE` (Größe des flüchtigen `/tmp`, Standard `64m`), `SANDBOX_WORK_VOLUME` (Volume für den persistenten `/work`-Bereich, Standard `sandbox-work`), `SANDBOX_NETWORK` (Standard `none`; z. B. `bridge` setzen, falls der Code Internetzugriff braucht — dann verlierst du den Netzwerk-Isolationsschutz).

#### Mehr Sprachen in der Sandbox

Mit dem Standard-Image `python:3.12-slim` kann die Sandbox **Python und Shell** (Debian-Basis, also Bash und die üblichen Kommandozeilen-Werkzeuge) — sonst nichts. Kein Java, kein Node, kein Compiler. Wenn ein Modell behauptet, es könne „C++, Rust, JS, falls installiert", ist das geraten; maßgeblich ist allein, was im Runner-Image liegt.

Das Repo bringt deshalb ein optionales mehrsprachiges Runner-Image mit (`sandbox-mcp/runner-multilang.Dockerfile`) — Python, Node/npm, Java (JDK), Go, gcc/g++/make, dazu git/curl/jq:

```bash
docker build -f sandbox-mcp/runner-multilang.Dockerfile \
  -t ai-stack-sandbox-runner:multilang sandbox-mcp/
```

Optional zusätzlich **PowerShell** (`pwsh`) — kostet ~200 MB und kommt aus Microsofts Paketquelle, deshalb standardmäßig aus:

```bash
docker build --build-arg WITH_POWERSHELL=1 \
  -f sandbox-mcp/runner-multilang.Dockerfile \
  -t ai-stack-sandbox-runner:multilang sandbox-mcp/
```

Dann in der `.env`:

```bash
SANDBOX_IMAGE=ai-stack-sandbox-runner:multilang
SANDBOX_MEM_LIMIT=2g
SANDBOX_TMPFS_SIZE=1g
SANDBOX_DEFAULT_TIMEOUT=60
SANDBOX_MAX_TIMEOUT=180
```

```bash
docker compose -f docker-compose.rocm.yml up -d sandbox-mcp
```

> ⚠️ **Die höheren Limits sind nicht optional.** `javac`, `go build` und `g++` scheitern an den Standardwerten (256 MB RAM, 64 MB `/tmp`, 15 s) zuverlässig — das Image allein zu tauschen reicht nicht.

**Bekannte Grenzen dieses Ansatzes:**

- **Kein Netzwerk** (Standard `SANDBOX_NETWORK=none`): `npm install`, `pip install`, `go get` und Gradle-Abhängigkeiten funktionieren nicht. Nur Standardbibliothek und was im Image liegt. Wer das braucht, muss `SANDBOX_NETWORK=bridge` setzen und den Isolationsschutz aufgeben.
- **Kein Zustand zwischen Aufrufen** — jeder Aufruf ist ein frischer Container. Mehrstufige Build-Vorgänge, die auf Zwischenständen aufbauen, gehen nicht.
- **Paketversionen kommen aus Debian stable** und sind entsprechend konservativ (z. B. Node 18, Go 1.19, JDK 17). Für neuere Versionen das Dockerfile anpassen.
- **PowerShell** ist standardmäßig nicht dabei, lässt sich aber beim Bauen dazuschalten (siehe unten). Windows-spezifische Cmdlets (Registry, WMI, Active Directory …) gibt es unter Linux naturgemäß auch dann nicht.
- **Android-App-Entwicklung geht in der Sandbox nicht** — SDK, Gradle und Emulator sprengen den Rahmen eines Wegwerf-Containers ohne Netzwerk. Dafür gibt es einen eigenen Dienst, siehe nächster Abschnitt.
