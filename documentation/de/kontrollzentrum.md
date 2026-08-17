# Kontrollzentrum (Menü)

Ein Menü für alles: sehen, was schon da ist, nachinstallieren, starten, entfernen.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/control-center.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · **Kontrollzentrum (Menü)** · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Öffnen

```bash
./stack-menu.sh          # oder gleichwertig:
./install.sh --menu
```

Der Kopf mit Logo und Zusammenfassung bleibt dabei **immer oben stehen** — auch während ein Befehl läuft. Die Ausgabe scrollt nur in dem Bereich darunter.

```
        ┌─┬─┬─┬─┐
    ┌───┴─┴─┴─┴───┐
    │  ▄▄     ▄▄  │      SELF-HOSTED
  ──┤  ██  ▄  ██  ├──    A I   S T A C K
    │  ▀▀  █  ▀▀  │
    └───┬─┬─┬─┬───┘
        └─┴─┴─┴─┘
  docker-compose.rocm.yml  ● Docker  Dienste: 12 läuft · 2 fehlt · 14 gesamt
  ────────────────────────────────────────────────────────────────────────
  Chat-Oberflächen
  ❯ Open WebUI             ● läuft       Chat-Oberfläche (Werkzeuge über mcpo)
    LibreChat              ◍ gestoppt    Zweite Oberfläche, MCP nativ
```

## Was du siehst

Jede Zeile zeigt, **in welchem Zustand dieser Baustein bei dir gerade ist** — genau das, was sonst mehrere `docker ps`-Aufrufe bräuchte:

| Anzeige | Bedeutung |
|---|---|
| ● läuft / bereit / installiert | Alles da und aktiv |
| ▲ teilweise | Von mehreren Containern läuft nur ein Teil (z. B. LibreChat ohne seine Datenbank) |
| ▲ ungesund | Container läuft, meldet aber einen fehlgeschlagenen Healthcheck |
| ◍ gestoppt / aus | Angelegt, läuft aber gerade nicht |
| ○ nicht da / fehlt / offen | Noch nicht installiert |

Die Kopfzeile fasst zusammen: Compose-Datei, Docker-Zustand, wie viele Dienste laufen und wie viele fehlen.

## Tasten

| Taste | Wirkung |
|---|---|
| `↑` `↓` bzw. `k` `j` | Eintrag wählen |
| `Enter` | Aktionen zu diesem Eintrag öffnen |
| `s` | Dienst starten (auf Dienst-Einträgen) |
| `x` | Dienst stoppen |
| `l` | Logs ansehen (letzte 200 Zeilen) |
| `r` | Status neu einlesen |
| `q` | Beenden |
| `Esc` | Aus einem Untermenü zurück |

## Die Bereiche

**Einrichtung** — `install.sh` starten, nur prüfen (`--check-only`, verändert nichts), Zugangsdaten anzeigen.

**Kern · Chat-Oberflächen · Werkzeuge · Wissensdatenbank · Zusatzdienste** — alle Dienste aus der Compose-Datei. Pro Dienst: starten, neu starten, stoppen, Logs, neu bauen, Container entfernen (Daten-Volumes bleiben dabei erhalten).

**CLI-Werkzeuge** — [Open Interpreter](open-interpreter.md). Kein Dienst, sondern ein Kommandozeilen-Werkzeug: hier siehst du, ob es gebaut ist, und startest es.

**System** — Docker, Docker Compose, GPU/ROCm, Firewall und `.env`. Jeder Punkt lässt sich anzeigen und (wo sinnvoll) ändern: Firewall-Regeln ansehen, Ports nur fürs LAN freigeben, `.env` bearbeiten.

**Aufräumen und entfernen** — von harmlos nach endgültig:

| Eintrag | Was passiert |
|---|---|
| Alles stoppen | Container halten an, nichts geht verloren |
| Alles neu starten | `up -d` über den ganzen Stack |
| MCP-Dienste neu starten | `restart-mcp.sh` — in der richtigen Reihenfolge, siehe [Betrieb](betrieb.md) |
| Ungenutztes aufräumen | Verwaiste Images und Build-Cache |
| Stack entfernen | Container weg, **Daten-Volumes bleiben** |
| Stack + alle Daten löschen | Modelle, Chats, Datenbank, `.env` — **endgültig** |
| Docker deinstallieren | Docker-Pakete vom System, optional `/var/lib/docker` |

> Die beiden letzten Punkte fragen nicht mit „ja/nein", sondern verlangen ein getipptes Wort (`loeschen` bzw. `docker weg`). Ein versehentliches Enter löscht damit nichts. **Docker deinstallieren trifft alle Container auf dem Rechner**, nicht nur diesen Stack.

## Wenn etwas nicht geht

Die Ausgabe jedes Befehls wird zusätzlich in eine Protokolldatei geschrieben; der Pfad steht nach dem Lauf unten am Bildschirm. Beim Beenden wird sie aufgeräumt — bei Bedarf also vorher kopieren.

| Symptom | Ursache |
|---|---|
| „stack-menu.sh braucht ein interaktives Terminal" | Über eine Pipe oder aus einem Skript gestartet — das Menü braucht ein echtes Terminal |
| Alles zeigt „nicht da", obwohl es läuft | Docker-Daemon nicht erreichbar, oder dein Benutzer ist nicht in der `docker`-Gruppe |
| Rahmen und Umlaute sind kaputt | Keine UTF-8-Locale — das Menü schaltet dann auf reines ASCII um; für die schöne Darstellung `LANG=de_DE.UTF-8` (oder `C.UTF-8`) setzen |
| Menü zeichnet Reste | Terminal zu klein; ab ca. 50×12 Zeichen wird es sinnvoll nutzbar |
| Zeilen laufen treppenförmig nach rechts | Behoben — trat vor `94e3c83` auf, weil das Terminal in den Rohmodus geschaltet wurde und damit `\n` den Wagenrücklauf verlor. `git pull` genügt |

Andere Compose-Datei benutzen:

```bash
COMPOSE_FILE=docker-compose.yml ./stack-menu.sh
NO_COLOR=1 ./stack-menu.sh          # ohne Farben
```
