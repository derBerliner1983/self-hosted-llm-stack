// Bündelt Excalidraws eigenen exportToBlob()-Renderer zu einer einzigen
// Datei, die ohne npm/Build-Werkzeuge im Browser läuft (siehe Dockerfile:
// wird nur einmal beim Bauen des Images mit esbuild erzeugt, zur Laufzeit
// lädt ein headless Chromium (Playwright) diese fertige bundle.js).
//
// So bekommt export_png() (server.py) EXAKT dieselbe Optik wie ein
// echtes Excalidraw im Browser - Handschrift-Schrift, echte Formen -
// ohne einen externen Dienst oder Netzwerk zur Laufzeit zu brauchen.
//
// This file is part of Self-Hosted AI Stack. MIT License.

import { exportToBlob } from "@excalidraw/excalidraw";

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

window.__renderReady = true;
