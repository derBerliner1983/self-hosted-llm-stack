# Austausch-Ablage

Ein Ordner, den du im Browser und das LLM gleichzeitig sehen — hoch-/runterladen auf beiden Seiten.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/exchange-bridge.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Kontrollzentrum (Menü)](kontrollzentrum.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android-Entwicklung](android.md) · **Austausch-Ablage** · [Wissensdatenbank (Vault)](wissensdatenbank.md) · [Modelle verwalten](modelle.md) · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Wozu

Ein Agent baut dir eine Android-App, schreibt ein Skript, erzeugt eine Datei — und dann? Ohne Ablage bleibt nur, den Quelltext aus dem Chat zu kopieren. Für eine fertig gebaute APK funktioniert das gar nicht erst.

Die Austausch-Ablage ist ein einfacher Ordner, den zwei Seiten gleichzeitig sehen:

- **Du im Browser** — Dateien hochladen, herunterladen, ansehen, löschen.
- **Das LLM über das Dateisystem-Werkzeug** (`mcp_gateway`, dasselbe wie beim [Vault](wissensdatenbank.md)) — lesen und schreiben.

Bewusst **nicht** der Vault selbst — der bleibt Wissensdatenbank, keine Ablage für Bau-Ergebnisse oder Testskripte.

## Adresse und Zugangsdaten

```
http://<server-ip>:8900
```

Zugangsdaten erzeugt `install.sh` automatisch (anders als beim rein lesenden [Dashboard](kontrollzentrum.md) gibt es hier auch Schreibzugriff — daher mit Passwort):

```bash
./scripts/service-credentials.sh exchange-bridge
```

Im [Kontrollzentrum](kontrollzentrum.md) steht dasselbe unter **Austausch-Ablage → Zugangsdaten anzeigen**.

Eigenen Benutzernamen/Passwort festlegen:

```bash
./scripts/set-credentials.sh exchange-bridge
```

(Das eigene Passwort wird — wie bei allen anderen Diensten mit dieser Funktion — **nicht** in der `.env` gespeichert. Näheres dazu in der [LibreChat-Doku](librechat.md#eigenen-benutzer-und-eigenes-passwort-festlegen), die dasselbe Verfahren einführt.)

## Im Chat nutzen

Sag dem Modell einfach, was es tun soll — es sieht `/exchange` automatisch über das Dateisystem-Werkzeug, sobald du es in LibreChat (`mcp_gateway`) oder Open WebUI aktivierst:

> Kopier die fertige APK nach /exchange, damit ich sie runterladen kann.

> Lies /exchange/testdaten.csv und werte sie aus.

Für den Android-Agenten ist das inzwischen fest hinterlegt: `gradle` (Werkzeug `create_project`/`gradle` in [android-mcp](android.md)) weiß, wohin eine gebaute APK gehört, und dass sie zum Download nach `/exchange` verschoben werden muss.

## Wie es funktioniert

```
Browser  <--HTTP, Basic-Auth-->  exchange-bridge  <--dasselbe Volume-->  mcp (Dateisystem-Werkzeug)
```

`exchange-bridge` ist ein kleiner, abhängigkeitsfreier Python-Dienst (kein Framework, wie [Dashboard](kontrollzentrum.md) und Vault-Bridge) — Liste, Hochladen, Herunterladen, Löschen, mit Basic Auth abgesichert. Dasselbe Docker-Volume hängt read-write im `mcp`-Container, eingetragen in `MCP_FILESYSTEM_DIRS` — das Dateisystem-Werkzeug sieht den Ordner deshalb ohne Umweg, genau wie `/vault` und `/workspace`.

## Grenzen

- **Kein Framework, kein Virenscan, keine Vorschau** — was du hochlädst, landet unverändert im Ordner. Für Dateien, denen du nicht traust, gilt dasselbe Vorsicht wie überall sonst.
- **Ein Upload-Limit pro Datei** existiert (`EXCHANGE_MAX_UPLOAD_MB`, Standard 500 MB) — kein Limit für die Ablage insgesamt. Bei wenig Plattenplatz im Blick behalten.
- **Kein Verzeichnisbaum** — die Ablage ist bewusst flach, ein Ordner, keine Unterordner. Für mehr Struktur bleibt der [Vault](wissensdatenbank.md) oder [Syncthing](wissensdatenbank.md#syncthing-alternative-zur-vault-bridge) die richtige Wahl.

## Einstellungen

| Variable | Standard | Bedeutung |
|---|---|---|
| `PORT_EXCHANGE_BRIDGE` | `8900` | Host-Port |
| `EXCHANGE_USER` | `admin` | Benutzername (Basic Auth) |
| `EXCHANGE_PASSWORD` | erzeugt | Passwort — leer, wenn ein eigenes gesetzt wurde |
| `EXCHANGE_MAX_UPLOAD_MB` | `500` | Grenze pro Datei |
| `URL_EXCHANGE_BRIDGE` | leer | Eigene Adresse (Reverse-Proxy) statt IP:Port |

## Entfernen

```bash
docker compose -f docker-compose.rocm.yml rm -sf exchange-bridge
docker volume rm exchange-data   # löscht die abgelegten Dateien unwiderruflich
```

Ohne den zweiten Befehl bleiben hochgeladene Dateien erhalten, falls der Dienst später wieder gebraucht wird.
