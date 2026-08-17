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
| `o` | Adresse des Dienstes anzeigen |
| `z` | Zugangsdaten des Dienstes anzeigen |
| `r` | Status neu einlesen |
| `q` | Beenden |
| `Esc` | Aus einem Untermenü zurück |

## Adressen der Dienste

Öffnest du einen Dienst mit `Enter`, steht seine Adresse gleich in der Überschrift; die Direkttaste `o` zeigt sie groß an:

```
  LibreChat  http://192.168.1.50:3080/

   ❯ Neu starten
     Adresse anzeigen (zum Anklicken)
     Adresse festlegen (eigene Domain / anderer Host)
```

Die Adresse wird aus dem Port (`.env`) und der IP des Rechners gebildet, auf dem das Menü läuft. In Terminals mit Verweis-Unterstützung — Windows Terminal, iTerm2, GNOME Terminal, WezTerm, Kitty — ist sie **anklickbar** und öffnet den Browser. PuTTY kann das nicht; dort steht die Adresse als Text zum Markieren und Kopieren. Abschalten mit `MENU_HYPERLINKS=0 ./stack-menu.sh`.

**Eigene Adresse hinterlegen** — etwa der Name hinter einem Reverse-Proxy: **Adresse festlegen**, Adresse eintippen, fertig. Sie landet als `URL_<DIENST>` in der `.env` und hat ab dann Vorrang. Fehlt `https://`, wird `http://` ergänzt. Leer lassen entfernt sie wieder.

| Dienst | Variable |
|---|---|
| Open WebUI | `URL_OPEN_WEBUI` |
| LibreChat | `URL_LIBRECHAT` |
| LiteLLM | `URL_LITELLM` |
| Dashboard | `URL_DASHBOARD` |
| Vault-Bridge | `URL_VAULT_BRIDGE` |
| Syncthing | `URL_SYNCTHING` |
| mcpo | `URL_MCPO` |
| MCP Gateway | `URL_MCP` |

`./scripts/show-credentials.sh` benutzt dieselben Werte. Erkennt das Menü die falsche IP (mehrere Netzwerkkarten), setz `STACK_HOST` in der `.env`.

## Zugangsdaten

Jeder Dienst hat im Menü **Zugangsdaten anzeigen** (Direkttaste `z`) — Adresse, Benutzer, Passwort bzw. Schlüssel, plus den Hinweis, wie die Anmeldung dort überhaupt funktioniert. Alles auf einmal gibt es unter **Einrichtung → Zugangsdaten anzeigen** oder auf der Kommandozeile:

```bash
./scripts/service-credentials.sh              # alle Dienste
./scripts/service-credentials.sh librechat    # nur einer
```

Bei drei Diensten kann das Menü das Standard-Konto auch **anlegen** (`Standard-Konto anlegen`, bzw. `--create`):

| Dienst | Was passiert |
|---|---|
| **LibreChat** | Konto über LibreChats eigenes `create-user`; Passwort aus der `.env` |
| **Open WebUI** | Registriert das Konto über die API der laufenden Instanz. Der Pfad wird aus deren OpenAPI-Beschreibung ermittelt statt fest eingebaut — Open WebUI ändert seine Routen zwischen Versionen. Findet sich keiner, sagt das Skript das und nennt die Daten fürs Registrieren im Browser |
| **Syncthing** | Setzt Benutzer und Passwort der Oberfläche (`syncthing generate`) und startet den Container neu |

Bei allen anderen gibt es nichts anzulegen: LiteLLM meldet sich mit `admin` und dem Master-Key an, Dashboard, mcpo und Vault-Bridge haben gar keine Anmeldung — dort steht stattdessen, warum sie nur ins LAN gehören.

Die Passwörter erzeugt `install.sh` einmalig zufällig und legt sie in der `.env` ab. Bewusst keine festen Standardpasswörter: diese Dienste kommen über die MCP-Werkzeuge an deinen Vault.

> Bei Syncthing prüft die Anzeige in der Konfiguration nach, ob das Passwort **wirklich** gesetzt ist — der Wert in der `.env` ist nur der Wunsch, bis `--create` gelaufen ist.

### Wenn Zugangsdaten „nicht gesetzt" sind

Dann fehlen die Schlüssel in deiner `.env`. Das passiert bei Installationen, die älter sind als die Schlüssel selbst: `install.sh` schreibt sie nur bei seinem eigenen Lauf.

**Das Menü merkt das von allein.** Beim Start prüft es die `.env` und fragt, wenn etwas fehlt:

```
.env ist unvollständig (ältere Installation). Jetzt neu aufbauen? Sicherung wird angelegt. [j/N]
```

Ein `j` genügt. Unter **System** steht die `.env` außerdem dauerhaft als `▲ lückenhaft`, mit demselben Punkt im Untermenü. Auf der Kommandozeile:

```bash
./scripts/env-repair.sh --check   # nur nachsehen, ändert nichts
./scripts/env-repair.sh           # Sicherung + neu aufbauen
```

**Was dabei passiert:** Die alte Datei wird gesichert (`.env.bak-<Zeitstempel>`, Rechte 600), dann wird eine neue, nach Abschnitten geordnete `.env` **auf Grundlage der alten** geschrieben. Alle vorhandenen Werte werden übernommen — auch die, die das Skript gar nicht kennt: eigene Adressen, geänderte Ports, selbst gesetzte Einträge. Die landen unverändert in einem Abschnitt „Eigene Einträge" am Ende. Ergänzt wird nur, was fehlt; Passwörter dabei einmalig zufällig.

> Das ist der Unterschied zu „neu anlegen": eine frische Datei aus der Vorlage würde deine eigenen Werte stillschweigend wegwerfen. Hier ist die alte Datei die Grundlage — und liegt als Sicherung trotzdem daneben.

Zusätzlich heilen sich die Skripte selbst: wer Zugangsdaten anzeigt oder ein Konto anlegt, bekommt fehlende Werte automatisch nachgetragen, mit einem Hinweis, was ergänzt wurde.

> Frisch erzeugte Passwörter gelten erst, wenn das Konto damit **angelegt** wird. Gibt es das Konto schon, sagt das Skript das und ändert nichts.

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
