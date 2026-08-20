// Bündelt Excalidraws eigenen exportToBlob()-Renderer UND den offiziellen
// Mermaid-Konverter zu einer einzigen Datei, die ohne npm/Build-Werkzeuge
// im Browser läuft (siehe Dockerfile: wird nur einmal beim Bauen des
// Images mit esbuild erzeugt, zur Laufzeit lädt ein headless Chromium
// (Playwright) diese fertige bundle.js).
//
// So bekommen export_png()/add_mermaid() (server.py) EXAKT dieselbe Optik
// und dasselbe Layout wie ein echtes Excalidraw im Browser (Handschrift-
// Schrift, echte Formen, Mermaids eigenes Layout-Ergebnis) - ohne einen
// externen Dienst oder Netzwerk zur Laufzeit zu brauchen.
//
// This file is part of Self-Hosted AI Stack. MIT License.

import { exportToBlob, convertToExcalidrawElements } from "@excalidraw/excalidraw";
import { parseMermaidToExcalidraw } from "@excalidraw/mermaid-to-excalidraw";

async function blobToBase64(blob) {
  const buf = await blob.arrayBuffer();
  let binary = "";
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

window.renderPNG = async function (sceneJson, optsJson) {
  const scene = JSON.parse(sceneJson);
  const opts = optsJson ? JSON.parse(optsJson) : {};
  const scale = opts.scale || 2;
  const blob = await exportToBlob({
    elements: scene.elements,
    appState: Object.assign(
      { exportBackground: true, viewBackgroundColor: "#ffffff" },
      scene.appState || {}
    ),
    files: scene.files || {},
    mimeType: "image/png",
    exportPadding: opts.padding != null ? opts.padding : 20,
    // getDimensions bekommt die NATÜRLICHE Größe (Inhalt + Padding) und
    // MUSS die tatsächliche Canvas-Pixelgröße zurückgeben, nicht die
    // natürliche Größe unverändert - sonst zeichnet exportToBlob mit
    // "scale" vergrößert auf eine zu klein gebliebene Leinwand, und das
    // Ergebnis ist oben links abgeschnitten (an einem echten Lauf
    // beobachtet, bevor width/height hier mit scale multipliziert wurden).
    getDimensions: (width, height) => ({
      width: width * scale,
      height: height * scale,
      scale,
    }),
  });
  return await blobToBase64(blob);
};

// Mermaid-Text (z. B. "flowchart TD\n  A[Start] --> B[Ende]") in fertig
// LAYOUTETE Excalidraw-Elemente umwandeln - löst genau das Problem, das
// add_element() bei vielen verbundenen Boxen hat: ein Modell kann x/y-
// Koordinaten für ein ganzes Diagramm nicht zuverlässig von Hand
// vergeben (überlappende Boxen/Linien, an einem echten Lauf beobachtet).
// Mermaids Layout-Engine (Sugiyama-artig, über parseMermaidToExcalidraw)
// übernimmt die Positionierung, das Modell muss nur noch Knoten und
// Kanten als Text beschreiben - das kann es zuverlässig.
//
// parseMermaidToExcalidraw liefert ein kompaktes "Skelett" (Boxen mit
// einem "label"-Feld statt eines eigenen, gebundenen Textelements) -
// convertToExcalidrawElements() aus dem Haupt-Excalidraw-Paket macht
// daraus vollständige, direkt speicherbare Elemente (u. a. die
// gebundenen Textelemente, die exportToBlob/eine echte .excalidraw-Datei
// erwarten). Ohne diesen zweiten Schritt bleiben die Boxen leer - so an
// einem echten Testlauf beobachtet.
window.mermaidToExcalidraw = async function (mermaidText) {
  const { elements: skeletons, files } = await parseMermaidToExcalidraw(mermaidText, {});
  const elements = convertToExcalidrawElements(skeletons);
  return JSON.stringify({ elements, files: files || {} });
};

window.__renderReady = true;
