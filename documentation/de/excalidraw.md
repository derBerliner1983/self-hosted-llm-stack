# Excalidraw

Das LLM baut Diagramme (Formen, Text, Pfeile) als `.excalidraw`-Datei oder direkt als PNG-Bild.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/excalidraw.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · **Excalidraw** · [Austausch-Ablage](austausch-ablage.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Wozu

`excalidraw-mcp` ist ein eigener, optionaler MCP-Dienst, mit dem das Modell Diagramme bauen kann — ein Flussdiagramm, eine Architekturskizze, eine Mindmap — ohne dass du selbst klicken musst.

**Wichtig zu wissen, bevor du es benutzt:** Dein laufender Excalidraw-Container (`excalidraw/excalidraw`, das offizielle Image) ist reine Frontend-Software ohne eigene Speicher- oder Sync-API. Das Modell zeichnet deshalb **nicht live** in eine offene Browser-Tab hinein — das bräuchte einen zusätzlichen Kollaborations-Server und wäre ein deutlich größerer, fragilerer Umbau. Stattdessen erzeugt das Modell Dateien und legt sie auf Wunsch nach [`/exchange`](austausch-ablage.md) — entweder als `.excalidraw` (zum Weiterbearbeiten in deinem Excalidraw über **Datei → Öffnen**) oder direkt als fertiges **PNG-Bild**.

## Im Chat nutzen

> Zeichne mir ein Flussdiagramm für einen Login-Prozess: Start, Eingabe prüfen, bei Fehler zurück zu Eingabe, bei Erfolg Ende. Exportier es als PNG nach /exchange.

Das Modell ruft dafür der Reihe nach auf:

1. `use_diagram(name)` — legt das Diagramm an (oder wählt ein bestehendes) und macht es zum **aktuellen** Diagramm.
2. `add_mermaid(text)` — baut das ganze Diagramm auf einen Schlag aus Mermaid-Text auf (siehe unten, warum das der empfohlene Weg ist).
3. `export_png()` — rendert die aktuelle Ansicht als PNG und kopiert es nach `/exchange`. Willst du beides (Bild UND die Rohdatei zum späteren Weiterbearbeiten in Excalidraw), nutze stattdessen `export_bundle()` — legt beides zusammen als `.zip` ab.

Danach: `/exchange` im Browser öffnen (siehe [Austausch-Ablage](austausch-ablage.md)) und die Datei herunterladen.

## Warum add_mermaid der empfohlene Weg ist

Bei einem Diagramm mit mehreren verbundenen Boxen (Flussdiagramm, Ablauf, Architektur, …) müsste ein Modell, das jede Box einzeln per `add_element` mit festen `x`/`y`-Koordinaten platziert, das komplette Layout im Kopf durchplanen — das schafft kein Sprachmodell zuverlässig. Live beobachtetes Ergebnis: Boxen und Linien liegen übereinander, sobald es mehr als eine Handvoll Elemente werden.

`add_mermaid(text)` umgeht das komplett: das Modell beschreibt nur noch **Knoten und Kanten als Text** (Mermaid-Syntax), zum Beispiel:

```
flowchart TD
    A[Start] --> B{Eingabe gueltig?}
    B -->|Nein| C[Fehler anzeigen]
    C --> A
    B -->|Ja| D[Fertig]
```

Die Positionierung übernimmt dann **Mermaids eigene Layout-Engine** (derselbe Code, den Excalidraw selbst für seinen "Mermaid importieren"-Knopf benutzt) — garantiert überschneidungsfrei, ganz ohne dass das Modell eine einzige Koordinate angeben muss. `add_mermaid` **ersetzt** dabei alle Elemente des aktuellen Diagramms (kein Hinzufügen wie bei `add_element`).

`add_element` bleibt für einzelne, freistehende Ergänzungen sinnvoll — für alles mit mehreren verbundenen Boxen ist `add_mermaid` die zuverlässige Wahl.

**Farbe:** Ohne Angabe bleiben Mermaid-Diagramme schwarz-weiß (Mermaids eigener Standard, kein Fehler). Für Farbe `classDef`/`class` verwenden:

```
flowchart TD
    A["Start"] --> B{"Eingabe gueltig?"}
    B -->|Ja| C["Fertig"]
    classDef ok fill:#b2f2bb,stroke:#2f9e44
    class A,C ok
```

**Zeilenumbrüche in Labels:** NIE `\n` oder `<br/>` in eine Beschriftung schreiben — beides bleibt als buchstäblicher Text stehen und wird vom Renderer zusätzlich an zufälligen Stellen umgebrochen, das Ergebnis ist Kauderwelsch (live beobachtet). Einfach normalen Text mit Leerzeichen schreiben ("Telefonnummer oder Drittanbieter") — Excalidraw bricht lange Labels von selbst sauber an Wortgrenzen um.

## Werkzeuge

| Werkzeug | Zweck |
|---|---|
| `list_diagrams()` | Vorhandene Diagramme auflisten, zeigt auch das aktuelle |
| `use_diagram(name)` | Diagramm anlegen/auswählen — wird zum "aktuellen" Diagramm |
| `add_mermaid(text)` | Aktuelles Diagramm aus Mermaid-Text aufbauen — **ersetzt** alle Elemente, automatisches Layout |
| `add_element(spec)` | Ein einzelnes Element zum aktuellen Diagramm hinzufügen |
| `remove_last_element()` | Letztes Element rückgängig machen |
| `get_diagram(name)` | Elemente eines Diagramms anzeigen (leerer Name = aktuelles) |
| `export_diagram(name)` | Als `.excalidraw`-Rohdatei nach `/exchange` kopieren (leerer Name = aktuelles) |
| `export_png(name)` | Als PNG-Bild nach `/exchange` rendern (leerer Name = aktuelles) |
| `export_bundle(name)` | PNG + `.excalidraw` zusammen als `.zip` nach `/exchange` (leerer Name = aktuelles) |

`export_png` rendert mit demselben Code, den Excalidraw selbst im Browser für "Bild exportieren" benutzt (echte Handschrift-Schrift, echte Formen) — nur headless über ein eingebautes Chromium (Playwright), ganz ohne deinen laufenden Excalidraw-Container oder Internet zur Laufzeit zu brauchen. Der erste Export nach dem Start des Dienstes dauert etwas länger (Chromium startet neu), danach ist jeder weitere in wenigen Sekunden fertig. Am zuverlässigsten unterstützt `add_mermaid`: Flussdiagramme (`flowchart`), Sequenzdiagramme (`sequenceDiagram`) und Klassendiagramme (`classDiagram`) — andere Mermaid-Diagrammarten können unvollständig umgesetzt werden.

`spec` bei `add_element` ist **ein JSON-Objekt als Text**, z. B.:

```json
{"type":"rectangle","x":100,"y":100,"width":240,"height":120,"text":"Start","backgroundColor":"#a5d8ff"}
```

Unterstützte `type`-Werte: `rectangle`, `ellipse`, `diamond` (alle drei optional mit `text` — wird zentriert eingefügt), `text` (eigenständig, braucht `x`/`y`/`text`), `arrow` und `line` (brauchen `x1`/`y1`/`x2`/`y2`). Alle Formen akzeptieren optional `strokeColor` (Hex-Farbe).

### Warum genau ein String-Parameter statt einzelner Koordinaten-Felder

An diesem Stack wurde beim Android-Werkzeug beobachtet, dass ein lokales Modell schon bei **zwei** einfachen String-Parametern in einem Aufruf (`name` + `package_name`) zuverlässig an der Schema-Validierung scheiterte, mit nur einem Parameter aber nicht (siehe [Werkzeuge fürs LLM](werkzeuge.md) zur Fehlersuche bei "did not match expected schema"). `add_element` und `add_mermaid` bekommen deshalb bewusst nur je einen String-Parameter. Modelle, die Code schreiben können, sind im Formulieren von Text (JSON oder Mermaid-Syntax) erfahrungsgemäß zuverlässiger als im Füllen mehrerer einzelner Funktionsargumente. Aus demselben Grund merkt sich der Dienst ein "aktuelles Diagramm" (`use_diagram`), statt den Namen bei jedem Aufruf erneut zu verlangen.

## Wie es funktioniert

```
LLM → add_mermaid()/add_element() → excalidraw-mcp (eigenes Volume) → export_diagram()/export_png() → /exchange → Browser (Download)
```

Ein Python-Dienst (Grundmuster wie [android-mcp](android.md) und die Code-Sandbox), der `.excalidraw`-JSON-Dateien in einem eigenen Docker-Volume verwaltet. `export_diagram()`/`export_png()` kopieren in dasselbe geteilte Volume, das auch [Austausch-Ablage](austausch-ablage.md) und `android-mcp` benutzen — kein zusätzlicher Zugangsdaten-Kram nötig, es ist nur ein Kopierziel.

Für `export_png()` und `add_mermaid()` steckt im Image zusätzlich Excalidraws eigener Renderer und der offizielle Mermaid-Konverter (`@excalidraw/mermaid-to-excalidraw` - einmalig beim Bauen des Images mit esbuild zu einer einzigen Datei gebündelt, keine Internetverbindung zur Laufzeit nötig) plus ein headless Chromium (Playwright) - deshalb ist dieses Image deutlich größer als die anderen MCP-Werkzeuge in diesem Stack, ähnlich wie bei [android-mcp](android.md).

## Konfiguration

Der Dienst ist optional. Wer keine Diagramme braucht, kann `excalidraw-mcp` aus `docker-compose.rocm.yml` ersatzlos streichen (dann auch den `excalidraw`-Eintrag in `librechat/librechat.yaml` und `mcpo/config.template.json` entfernen).

Fehlersuche wie bei jedem anderen MCP-Werkzeug: `./scripts/diagnose-mcp.sh`.
