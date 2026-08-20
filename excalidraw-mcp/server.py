"""MCP-Dienst für Excalidraw-Diagramme.

Baut KEINE Live-Verbindung in eine offene Excalidraw-Browser-Tab - der
mitgelieferte Vanilla-Container (excalidraw/excalidraw) ist reine
Frontend-Software ohne eigene Speicher-/Sync-API dafür, und ein
Kollaborations-Server (WebSocket) wäre ein eigenes, deutlich fragileres
Projekt gewesen. Stattdessen schreibt dieser Dienst .excalidraw-Dateien
(das offizielle, offene Dateiformat) in einen eigenen Arbeitsbereich und
legt sie auf Wunsch nach /exchange - von dort öffnest du sie in deinem
laufenden Excalidraw über "Datei" -> "Öffnen".

Werkzeuge für das Modell:
  - list_diagrams()          Vorhandene Diagramme auflisten
  - use_diagram(name)        Diagramm anlegen/auswählen (wird "aktuell")
  - add_element(spec)        Ein Element zum AKTUELLEN Diagramm hinzufügen
  - add_mermaid(text)        AKTUELLES Diagramm aus Mermaid-Text aufbauen (ERSETZT Elemente)
  - remove_last_element()    Letztes Element rückgängig machen
  - get_diagram(name)        Elemente eines Diagramms anzeigen
  - export_diagram(name)     Nach /exchange kopieren, zum Herunterladen (.excalidraw)
  - export_png(name)         Als PNG-Bild nach /exchange rendern

export_png()/add_mermaid() rendern bzw. layouten mit demselben Code, den
Excalidraw selbst im Browser benutzt (exportToBlob bzw. der offizielle
Mermaid-Konverter @excalidraw/mermaid-to-excalidraw, siehe
render/entry.js) - nur headless über Playwright/Chromium statt in einer
sichtbaren Tab. Dafür startet dieser Dienst beim Hochfahren einen
kleinen, rein lokalen HTTP-Server (127.0.0.1, EXCALIDRAW_RENDER_PORT),
der render/bundle.js und die Schriftdateien ausliefert - Chromium
braucht eine echte URL, kein file://, um Schriften per fetch()
nachzuladen (siehe harness.html).

WICHTIG zur Werkzeugwahl bei MEHREREN verbundenen Boxen: add_mermaid
benutzen, NICHT mehrere add_element-Aufrufe. add_element verlangt x/y je
Box von Hand - das führt bei mehr als ein paar Boxen zuverlässig zu
Überlappungen, weil kein Sprachmodell ein ganzes Layout im Kopf plant
(an einem echten Lauf beobachtet: Text und Linien übereinander, siehe
add_mermaid()-Docstring für ein Beispiel). Mermaids eigene Layout-Engine
übernimmt das Positionieren zuverlässig - das Modell beschreibt nur
Knoten und Kanten als Text.

WICHTIG zum Werkzeug-Zuschnitt: add_element() nimmt bewusst GENAU EINEN
String-Parameter (ein JSON-Objekt als Text) statt vieler einzelner
Parameter (x, y, width, height, Farbe, ...). Grund: an genau diesem Stack
wurde beobachtet, dass ein lokales Modell schon bei ZWEI einfachen
String-Parametern in einem Aufruf ("name" + "package_name" bei
android-mcp) zuverlässig an der Schema-Validierung scheiterte, mit einem
einzigen Parameter aber nicht. Ein JSON-Blob in einem einzigen String-Feld
umgeht das - Modelle, die Code schreiben können (wie hier explizit
gewünscht), sind im Formulieren von JSON als TEXT erfahrungsgemäß
zuverlässiger als im Füllen mehrerer einzelner Funktionsargumente.
Ebenso deshalb: ein "aktuelles Diagramm" (use_diagram) statt den
Diagrammnamen bei jedem add_element-Aufruf erneut mitzugeben.

This file is part of Self-Hosted AI Stack. MIT License.
"""

import base64
import errno
import functools
import http.server
import json
import os
import random
import re
import threading
import time
import uuid

from mcp.server.mcpserver import MCPServer
from playwright.sync_api import sync_playwright

WORKSPACE = os.environ.get("EXCALIDRAW_WORKSPACE", "/diagrams")
EXCHANGE_DIR = os.environ.get("EXCALIDRAW_EXCHANGE_DIR", "/exchange")
CURRENT_FILE = os.path.join(WORKSPACE, ".current")

# Für export_png(): Verzeichnis mit dem gebündelten Renderer (bundle.js,
# harness.html, fonts/), von einem lokalen HTTP-Server ausgeliefert -
# siehe Dockerfile (Stufe "jsbuild") und render/entry.js.
RENDER_DIR = os.environ.get("EXCALIDRAW_RENDER_DIR", "/app/render")
RENDER_PORT = int(os.environ.get("EXCALIDRAW_RENDER_PORT", "8934"))
# Kein expliziter Pfad zu Chromium nötig: das offizielle Playwright-
# Basisimage (siehe Dockerfile) hat den Browser schon an der Stelle
# installiert, an der Playwright selbst ihn erwartet.

HOST = os.environ.get("FASTMCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("FASTMCP_PORT", "8000"))

mcp = MCPServer("Excalidraw")

# Diagrammnamen landen unveraendert in Pfaden - deshalb streng validieren,
# damit "../" oder absolute Pfade nicht aus dem Arbeitsbereich ausbrechen
# (dasselbe Muster wie android-mcp/server.py: _NAME_RE).
_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,63}$")
_SHAPE_TYPES = {"rectangle", "ellipse", "diamond"}
_ALL_TYPES = _SHAPE_TYPES | {"text", "arrow", "line"}


def _diagram_path(name):
    if not _NAME_RE.match(name or ""):
        raise ValueError(
            "Ungültiger Diagrammname. Erlaubt: Buchstabe am Anfang, danach "
            "Buchstaben/Ziffern/Unterstrich/Bindestrich, max. 64 Zeichen."
        )
    path = os.path.realpath(os.path.join(WORKSPACE, name + ".excalidraw"))
    if os.path.commonpath([path, os.path.realpath(WORKSPACE)]) != os.path.realpath(WORKSPACE):
        raise ValueError("Diagrammpfad liegt außerhalb des Arbeitsbereichs.")
    return path


def _empty_scene():
    return {
        "type": "excalidraw",
        "version": 2,
        "source": "self-hosted-llm-stack/excalidraw-mcp",
        "elements": [],
        "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"},
        "files": {},
    }


def _load_scene(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _save_scene(path, scene):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(scene, fh, indent=2)


def _get_current():
    try:
        with open(CURRENT_FILE, "r", encoding="utf-8") as fh:
            name = fh.read().strip()
    except OSError:
        return None
    return name or None


def _set_current(name):
    with open(CURRENT_FILE, "w", encoding="utf-8") as fh:
        fh.write(name)


def _require_current():
    """Liefert (name, path, scene) des aktuellen Diagramms oder wirft
    ValueError mit einer für das Modell verständlichen Meldung."""
    name = _get_current()
    if not name:
        raise ValueError(
            "Kein aktuelles Diagramm. Ruf zuerst use_diagram(name) auf."
        )
    path = _diagram_path(name)
    if not os.path.exists(path):
        raise ValueError(
            f"Aktuelles Diagramm '{name}' existiert nicht mehr. "
            "Ruf use_diagram(name) erneut auf."
        )
    return name, path, _load_scene(path)


# ── Excalidraw-Element-Aufbau ────────────────────────────────────────────
# Excalidraws eigener Datei-Import (restoreElements) füllt fehlende
# optionale Felder beim Öffnen selbst auf - hier reicht es, alle Felder zu
# setzen, die für ein sauberes erstes Rendern nötig sind, es muss keine
# 1:1-Kopie der internen Runtime-Repräsentation sein.

def _new_id():
    return uuid.uuid4().hex[:20]


def _base_fields(type_, x, y, width, height, stroke_color, background_color):
    now_ms = int(time.time() * 1000)
    return {
        "id": _new_id(),
        "type": type_,
        "x": float(x),
        "y": float(y),
        "width": float(width),
        "height": float(height),
        "angle": 0,
        "strokeColor": stroke_color,
        "backgroundColor": background_color,
        "fillStyle": "solid",
        "strokeWidth": 2,
        "strokeStyle": "solid",
        "roughness": 1,
        "opacity": 100,
        "groupIds": [],
        "frameId": None,
        "roundness": {"type": 3} if type_ == "rectangle" else None,
        "seed": random.randint(1, 2**31 - 1),
        "version": 1,
        "versionNonce": random.randint(1, 2**31 - 1),
        "isDeleted": False,
        "boundElements": None,
        "updated": now_ms,
        "link": None,
        "locked": False,
    }


def _make_text_element(x, y, text, font_size, stroke_color, container_id=None,
                        text_align="left", vertical_align="top"):
    # Grobe Schätzung der Breite/Höhe über die Zeichenanzahl - Excalidraw
    # misst beim Öffnen mit der echten Schrift nach, das hier muss nur für
    # eine erste, brauchbare Darstellung reichen.
    width = max(10.0, len(text) * font_size * 0.55)
    height = font_size * 1.25
    el = _base_fields("text", x, y, width, height, stroke_color, "transparent")
    el.update({
        "text": text,
        "originalText": text,
        "fontSize": font_size,
        "fontFamily": 1,  # 1 = Excalidraw-Handschrift ("Virgil")
        "textAlign": text_align,
        "verticalAlign": vertical_align,
        "baseline": font_size,
        "containerId": container_id,
        "lineHeight": 1.25,
    })
    return el


def _make_shape_element(type_, x, y, width, height, stroke_color, background_color, text):
    el = _base_fields(type_, x, y, width, height, stroke_color, background_color)
    if not text:
        return [el]
    font_size = 20
    text_el = _make_text_element(
        x, y, text, font_size, stroke_color,
        container_id=el["id"], text_align="center", vertical_align="middle",
    )
    # Textelement über der Form zentrieren.
    text_el["x"] = x + (width - text_el["width"]) / 2
    text_el["y"] = y + (height - text_el["height"]) / 2
    el["boundElements"] = [{"type": "text", "id": text_el["id"]}]
    return [el, text_el]


def _make_linear_element(type_, x1, y1, x2, y2, stroke_color):
    x = min(x1, x2)
    y = min(y1, y2)
    width = abs(x2 - x1)
    height = abs(y2 - y1)
    el = _base_fields(type_, x, y, width, height, stroke_color, "transparent")
    el.update({
        "points": [[x1 - x, y1 - y], [x2 - x, y2 - y]],
        "lastCommittedPoint": None,
        "startBinding": None,
        "endBinding": None,
        "startArrowhead": None,
        "endArrowhead": "arrow" if type_ == "arrow" else None,
    })
    return [el]


def _build_elements(spec):
    """spec: bereits als dict geparstes JSON-Objekt für EIN Element."""
    type_ = spec.get("type")
    if type_ not in _ALL_TYPES:
        raise ValueError(
            f"Unbekannter oder fehlender 'type': {type_!r}. "
            f"Erlaubt: {', '.join(sorted(_ALL_TYPES))}."
        )
    stroke_color = spec.get("strokeColor", "#1e1e1e")

    if type_ in _SHAPE_TYPES:
        for key in ("x", "y", "width", "height"):
            if key not in spec:
                raise ValueError(f"'{type_}' braucht '{key}'.")
        return _make_shape_element(
            type_, spec["x"], spec["y"], spec["width"], spec["height"],
            stroke_color, spec.get("backgroundColor", "transparent"),
            spec.get("text"),
        )

    if type_ == "text":
        for key in ("x", "y", "text"):
            if key not in spec:
                raise ValueError(f"'text' braucht '{key}'.")
        return [_make_text_element(
            spec["x"], spec["y"], spec["text"],
            spec.get("fontSize", 20), stroke_color,
        )]

    # arrow / line
    for key in ("x1", "y1", "x2", "y2"):
        if key not in spec:
            raise ValueError(f"'{type_}' braucht '{key}'.")
    return _make_linear_element(
        type_, spec["x1"], spec["y1"], spec["x2"], spec["y2"], stroke_color,
    )


@mcp.tool()
def list_diagrams() -> dict:
    """START HIER. Listet vorhandene Excalidraw-Diagramme auf und zeigt,
    welches gerade "aktuell" ist (siehe use_diagram).
    """
    try:
        names = sorted(
            f[:-len(".excalidraw")]
            for f in os.listdir(WORKSPACE)
            if f.endswith(".excalidraw")
        )
    except OSError as exc:
        return {"error": str(exc), "diagrams": []}

    diagrams = []
    for name in names:
        try:
            scene = _load_scene(_diagram_path(name))
            count = len(scene.get("elements", []))
        except (OSError, ValueError, json.JSONDecodeError):
            count = None
        diagrams.append({"name": name, "elements": count})
    return {"workspace": WORKSPACE, "current": _get_current(), "diagrams": diagrams}


@mcp.tool()
def use_diagram(name: str) -> dict:
    """Legt ein Diagramm an (falls es noch nicht existiert) und macht es
    zum AKTUELLEN Diagramm - add_element(), get_diagram() ohne Namen und
    export_diagram() ohne Namen beziehen sich danach darauf.

    :param name: Diagrammname (Buchstaben, Ziffern, _ und -).
    """
    try:
        path = _diagram_path(name)
    except ValueError as exc:
        return {"error": str(exc)}

    created = False
    if not os.path.exists(path):
        _save_scene(path, _empty_scene())
        created = True

    _set_current(name)
    scene = _load_scene(path)
    return {"diagram": name, "created": created, "elements": len(scene.get("elements", []))}


@mcp.tool()
def add_element(spec: str) -> dict:
    """Fügt EIN Element zum AKTUELLEN Diagramm hinzu (vorher use_diagram()
    aufrufen). 'spec' ist ein JSON-Objekt ALS TEXT mit den Feldern für
    genau ein Element - kein Python-Dict, ein String mit gültigem JSON.

    Formen von 'spec' (Koordinaten in Pixeln, Ursprung oben links):

      Rechteck/Ellipse/Raute:
        {"type":"rectangle","x":100,"y":100,"width":240,"height":120,
         "text":"Start","backgroundColor":"#a5d8ff"}
        (type: "rectangle", "ellipse" oder "diamond". "text" ist optional -
        wird als zentrierte Beschriftung in die Form eingefügt.
        "backgroundColor" optional, Standard "transparent".)

      Text ohne Form:
        {"type":"text","x":100,"y":100,"text":"Überschrift","fontSize":28}

      Pfeil/Linie:
        {"type":"arrow","x1":100,"y1":100,"x2":300,"y2":100}
        (type: "arrow" oder "line".)

    Alle Formen akzeptieren optional "strokeColor" (Standard "#1e1e1e",
    Hex-Farbe). Für ein Flussdiagramm: mehrere Formen mit add_element
    anlegen, dann Pfeile zwischen ihren Mittelpunkten ziehen.

    :param spec: JSON-Objekt für ein Element, siehe oben.
    """
    try:
        name, path, scene = _require_current()
    except ValueError as exc:
        return {"error": str(exc)}

    try:
        parsed = json.loads(spec)
    except json.JSONDecodeError as exc:
        return {"error": f"'spec' ist kein gültiges JSON: {exc}"}
    if not isinstance(parsed, dict):
        return {"error": "'spec' muss ein JSON-OBJEKT sein (ein Element), kein Array."}

    try:
        new_elements = _build_elements(parsed)
    except ValueError as exc:
        return {"error": str(exc)}

    scene.setdefault("elements", []).extend(new_elements)
    _save_scene(path, scene)
    return {
        "diagram": name,
        "added": new_elements[0]["id"],
        "elements_total": len(scene["elements"]),
    }


@mcp.tool()
def remove_last_element() -> dict:
    """Entfernt das zuletzt hinzugefügte Element (bzw. Formpaar aus Form +
    Beschriftung) aus dem AKTUELLEN Diagramm. Nützlich, um einen
    Fehlgriff bei add_element rückgängig zu machen, ohne das ganze
    Diagramm neu anzufangen.
    """
    try:
        name, path, scene = _require_current()
    except ValueError as exc:
        return {"error": str(exc)}

    elements = scene.get("elements", [])
    if not elements:
        return {"error": f"'{name}' hat keine Elemente."}

    last = elements[-1]
    removed = [last["id"]]
    elements.pop()
    # Bei einer beschrifteten Form wurden zwei Elemente auf einmal
    # hinzugefügt (Form + gebundener Text) - beide wieder entfernen, sonst
    # bliebe eine verwaiste Form ohne ihre Beschriftung zurück.
    if last.get("type") == "text" and elements and elements[-1].get("boundElements"):
        bound_ids = {b["id"] for b in elements[-1]["boundElements"]}
        if last["id"] in bound_ids:
            removed.append(elements[-1]["id"])
            elements.pop()

    _save_scene(path, scene)
    return {"diagram": name, "removed": removed, "elements_total": len(elements)}


@mcp.tool()
def get_diagram(name: str = "") -> dict:
    """Zeigt die Elemente eines Diagramms (kompakt, ohne die vielen
    Render-Detailfelder) - nützlich, um vor dem Weitermachen zu prüfen,
    was schon da ist, z. B. um eine freie Stelle für die nächste Form zu
    finden oder einen Pfeil an die richtige Stelle zu setzen.

    :param name: Diagrammname. Leer = aktuelles Diagramm (siehe use_diagram).
    """
    if not name:
        try:
            name, path, scene = _require_current()
        except ValueError as exc:
            return {"error": str(exc)}
    else:
        try:
            path = _diagram_path(name)
        except ValueError as exc:
            return {"error": str(exc)}
        if not os.path.exists(path):
            return {"error": f"Diagramm '{name}' nicht gefunden. Siehe list_diagrams()."}
        scene = _load_scene(path)

    compact = [
        {
            "id": el.get("id"),
            "type": el.get("type"),
            "x": el.get("x"),
            "y": el.get("y"),
            "width": el.get("width"),
            "height": el.get("height"),
            "text": el.get("text"),
        }
        for el in scene.get("elements", [])
    ]
    return {"diagram": name, "elements": compact}


# ── PNG-Rendern (export_png) ─────────────────────────────────────────────

_render_server_started = False
_render_lock = threading.Lock()


def _ensure_render_server():
    """Startet den lokalen Datei-Server für render/ - idempotent, auch
    prozessübergreifend.

    Playwright/Chromium braucht eine echte HTTP-URL, kein file:// - sonst
    scheitert das Nachladen der Schriften per fetch() (an einem echten Lauf
    beobachtet: file:// führte zu "NetworkError", Chromiums Fetch-API
    erlaubt keine file://-Ziele von einer file://-Seite aus). Der Server
    läuft nur auf 127.0.0.1, ist also von außerhalb dieses Containers
    ohnehin nicht erreichbar.

    Das globale _render_server_started-Flag allein reicht nicht: FastMCP
    kann parallele Werkzeugaufrufe in eigenen Worker-Prozessen bedienen,
    von denen jeder mit einem frischen, eigenen False startet - an einem
    echten Lauf beobachtet als "[Errno 98] Address already in use", weil
    ein PARALLELER Aufruf den Port im selben Moment schon belegt hatte.
    Ein bereits belegter Port ist hier kein Fehler: irgendein Worker
    liefert render/ dann bereits aus - alle Worker liefern exakt denselben
    Inhalt aus, es kommt nicht darauf an, welcher zuerst gebunden hat.
    """
    global _render_server_started
    if _render_server_started:
        return
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=RENDER_DIR)
    try:
        httpd = http.server.ThreadingHTTPServer(("127.0.0.1", RENDER_PORT), handler)
    except OSError as exc:
        if exc.errno == errno.EADDRINUSE:
            _render_server_started = True  # ein anderer Worker bedient den Port bereits
            return
        raise
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    _render_server_started = True


def _render_png_bytes(scene, scale=2):
    """Rendert eine Szene mit einem headless Chromium zu PNG-Bytes.

    Ein Lock statt mehrerer gleichzeitiger Chromium-Prozesse: export_png
    ist ein gelegentlich genutztes Werkzeug, kein Dauerbetrieb - lieber
    Aufrufe kurz hintereinander abarbeiten als den Speicher mit mehreren
    Browserinstanzen gleichzeitig zu belasten.
    """
    _ensure_render_server()
    with _render_lock:
        with sync_playwright() as p:
            browser = p.chromium.launch(args=["--no-sandbox"])
            try:
                page = browser.new_page()
                page.goto(f"http://127.0.0.1:{RENDER_PORT}/harness.html")
                page.wait_for_function("window.__renderReady === true", timeout=15000)
                b64 = page.evaluate(
                    "([sceneJson, optsJson]) => window.renderPNG(sceneJson, optsJson)",
                    [json.dumps(scene), json.dumps({"scale": scale})],
                )
            finally:
                browser.close()
    return base64.b64decode(b64)


def _render_mermaid_elements(mermaid_text):
    """Wandelt Mermaid-Text in fertig layoutete Excalidraw-Elemente um -
    per Mermaids eigener Layout-Engine, im selben headless Chromium wie
    _render_png_bytes()."""
    _ensure_render_server()
    with _render_lock:
        with sync_playwright() as p:
            browser = p.chromium.launch(args=["--no-sandbox"])
            try:
                page = browser.new_page()
                page.goto(f"http://127.0.0.1:{RENDER_PORT}/harness.html")
                page.wait_for_function("window.__renderReady === true", timeout=15000)
                result_json = page.evaluate(
                    "(text) => window.mermaidToExcalidraw(text)", mermaid_text
                )
            finally:
                browser.close()
    return json.loads(result_json)


@mcp.tool()
def add_mermaid(text: str) -> dict:
    """Baut das AKTUELLE Diagramm komplett aus Mermaid-Text auf - ERSETZT
    dabei alle bisherigen Elemente (kein Hinzufügen wie add_element).

    Für alles mit MEHREREN verbundenen Boxen/Pfeilen ist das der bessere
    Weg als viele einzelne add_element-Aufrufe: bei add_element musst du
    x/y für jede Box selbst festlegen - bei mehr als ein paar Boxen führt
    das zuverlässig zu Überlappungen (an echten Läufen beobachtet).
    add_mermaid lässt stattdessen Mermaids eigene Layout-Engine
    entscheiden, wo jede Box hinkommt - keine Koordinaten nötig, nur
    Knoten und Kanten als Text beschreiben.

    Beispiel für 'text' (Flussdiagramm, oben nach unten):
        flowchart TD
            A[Start] --> B{Eingabe gueltig?}
            B -->|Nein| C[Fehler anzeigen]
            C --> A
            B -->|Ja| D[Fertig]

    Am zuverlässigsten unterstützt: flowchart, sequenceDiagram,
    classDiagram. Andere Mermaid-Diagrammarten können unvollständig
    umgesetzt werden.

    :param text: Vollständiger Mermaid-Diagrammtext (siehe Beispiel).
    """
    try:
        name, path, scene = _require_current()
    except ValueError as exc:
        return {"error": str(exc)}

    try:
        result = _render_mermaid_elements(text)
    except Exception as exc:  # noqa: BLE001 - Playwright/Mermaid können diverse Fehler werfen
        return {"error": f"Mermaid-Text konnte nicht umgesetzt werden: {exc}"}

    elements = result.get("elements", [])
    if not elements:
        return {"error": "Mermaid-Text ergab keine Elemente - Syntax prüfen."}

    scene["elements"] = elements
    scene["files"] = result.get("files", {})
    _save_scene(path, scene)
    return {
        "diagram": name,
        "elements_total": len(elements),
        "next_step": "Mit export_png() oder export_diagram() nach /exchange exportieren.",
    }


@mcp.tool()
def export_png(name: str = "") -> dict:
    """Rendert ein Diagramm als PNG-Bild und legt es nach /exchange - wie
    export_diagram, nur als fertiges Bild statt als .excalidraw-Rohdatei.

    Nutzt denselben Renderer, den Excalidraw selbst im Browser verwendet
    (echte Handschrift-Schrift, echte Formen) - läuft aber headless in
    diesem Dienst, kein externer Dienst oder Netzwerk zur Laufzeit nötig.
    Der erste Aufruf nach dem Start dauert etwas länger (Chromium startet
    neu), danach ist jeder Export in wenigen Sekunden fertig.

    :param name: Diagrammname. Leer = aktuelles Diagramm (siehe use_diagram).
    """
    if not name:
        try:
            name, path, scene = _require_current()
        except ValueError as exc:
            return {"error": str(exc)}
    else:
        try:
            path = _diagram_path(name)
        except ValueError as exc:
            return {"error": str(exc)}
        if not os.path.exists(path):
            return {"error": f"Diagramm '{name}' nicht gefunden. Siehe list_diagrams()."}
        scene = _load_scene(path)

    if not scene.get("elements"):
        return {"error": f"'{name}' hat keine Elemente - erst mit add_element etwas hinzufügen."}

    try:
        png_bytes = _render_png_bytes(scene)
    except Exception as exc:  # noqa: BLE001 - Playwright kann diverse Fehlerarten werfen
        return {"error": f"Rendern fehlgeschlagen: {exc}"}

    try:
        os.makedirs(EXCHANGE_DIR, exist_ok=True)
        dest = os.path.join(EXCHANGE_DIR, f"{name}.png")
        with open(dest, "wb") as fh:
            fh.write(png_bytes)
    except OSError as exc:
        return {"error": f"Konnte nicht nach {EXCHANGE_DIR} kopieren: {exc}"}

    return {
        "diagram": name,
        "exchange_path": dest,
        "next_step": f"'{name}.png' liegt jetzt in /exchange - der Nutzer kann es dort direkt als Bild herunterladen.",
    }


@mcp.tool()
def export_diagram(name: str = "") -> dict:
    """Kopiert ein Diagramm nach /exchange, damit der Nutzer es im Browser
    herunterladen und in seinem Excalidraw über "Datei -> Öffnen" laden
    kann - genau wie android-mcp fertige APKs dorthin legt.

    :param name: Diagrammname. Leer = aktuelles Diagramm (siehe use_diagram).
    """
    if not name:
        try:
            name, path, _ = _require_current()
        except ValueError as exc:
            return {"error": str(exc)}
    else:
        try:
            path = _diagram_path(name)
        except ValueError as exc:
            return {"error": str(exc)}
        if not os.path.exists(path):
            return {"error": f"Diagramm '{name}' nicht gefunden. Siehe list_diagrams()."}

    try:
        os.makedirs(EXCHANGE_DIR, exist_ok=True)
        dest = os.path.join(EXCHANGE_DIR, f"{name}.excalidraw")
        with open(path, "r", encoding="utf-8") as src, open(dest, "w", encoding="utf-8") as dst:
            dst.write(src.read())
    except OSError as exc:
        return {"error": f"Konnte nicht nach {EXCHANGE_DIR} kopieren: {exc}"}

    return {
        "diagram": name,
        "exchange_path": dest,
        "next_step": (
            f"'{name}.excalidraw' liegt jetzt in /exchange. Der Nutzer lädt "
            "es dort herunter und öffnet es in Excalidraw über "
            "\"Datei\" -> \"Öffnen\"."
        ),
    }


if __name__ == "__main__":
    os.makedirs(WORKSPACE, exist_ok=True)
    mcp.run(transport="streamable-http", host=HOST, port=PORT)
