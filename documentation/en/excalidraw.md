# Excalidraw

The LLM builds diagrams (shapes, text, arrows) as an `.excalidraw` file or directly as a PNG image.

[Deutsche Version](../de/excalidraw.md) &nbsp;|&nbsp; [Back to overview](../../README-en.md)

**Documentation:** [Installation & getting started](installation.md) · [Control center (menu)](control-center.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [LibreChat (second UI)](librechat.md) · [Code sandbox](code-sandbox.md) · [Open Interpreter (CLI)](open-interpreter.md) · [Android development](android.md) · **Excalidraw** · [Exchange Bridge](exchange-bridge.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · [Security & remote access](security.md) · [Other stacks](other-stacks.md)

---

## Why

`excalidraw-mcp` is a separate, optional MCP service that lets the model build diagrams — a flowchart, an architecture sketch, a mind map — without you clicking anything yourself.

**Important to know before you use it:** your running Excalidraw container (`excalidraw/excalidraw`, the official image) is pure frontend software with no storage or sync API of its own. The model therefore does **not** draw live into an open browser tab — that would need an additional collaboration server and would be a much bigger, more fragile change. Instead the model generates files and, on request, drops them into [`/exchange`](exchange-bridge.md) — either as `.excalidraw` (to keep editing in your own Excalidraw via **File → Open**) or directly as a finished **PNG image**.

## Using it in chat

> Draw me a flowchart for a login flow: start, validate input, back to input on error, end on success. Export it as PNG to /exchange.

The model calls, in order:

1. `use_diagram(name)` — creates the diagram (or picks an existing one) and makes it the **current** diagram.
2. `add_element(spec)` — repeatedly, one rectangle/ellipse/text/arrow per call.
3. `export_png()` — renders the current diagram as PNG and copies it to `/exchange`. Want the raw file to keep editing instead? Use `export_diagram()`.

Afterwards: open `/exchange` in your browser (see [Exchange Bridge](exchange-bridge.md)) and download the file.

## Tools

| Tool | Purpose |
|---|---|
| `list_diagrams()` | List existing diagrams, also shows the current one |
| `use_diagram(name)` | Create/select a diagram — becomes the "current" diagram |
| `add_element(spec)` | Add one element to the current diagram |
| `remove_last_element()` | Undo the last element |
| `get_diagram(name)` | Show a diagram's elements (empty name = current) |
| `export_diagram(name)` | Copy the raw `.excalidraw` file to `/exchange` (empty name = current) |
| `export_png(name)` | Render as a PNG image to `/exchange` (empty name = current) |

`export_png` renders with the exact same code Excalidraw itself uses in the browser for "Export image" (real hand-drawn font, real shapes) — just headless, via a bundled Chromium (Playwright), with no dependency on your running Excalidraw container or the internet at runtime. The first export after the service starts takes a little longer (Chromium has to launch), every export after that finishes in a few seconds.

`add_element`'s `spec` is **one JSON object as text**, e.g.:

```json
{"type":"rectangle","x":100,"y":100,"width":240,"height":120,"text":"Start","backgroundColor":"#a5d8ff"}
```

Supported `type` values: `rectangle`, `ellipse`, `diamond` (all three optionally take `text` — inserted centered), `text` (standalone, needs `x`/`y`/`text`), and `arrow`/`line` (need `x1`/`y1`/`x2`/`y2`). All shapes optionally accept `strokeColor` (hex color).

### Why one string parameter instead of individual coordinate fields

On this stack, the Android tool showed that a local model reliably failed schema validation with just **two** simple string parameters in one call (`name` + `package_name`), but not with a single one (see [Tools for the LLM](tools.md) for troubleshooting "did not match expected schema"). `add_element` therefore deliberately takes only `spec` — a JSON object as text. Models that can write code tend to be more reliable at formulating JSON as text than at filling in several separate function arguments. For the same reason, the service remembers a "current diagram" (`use_diagram`) instead of requiring the name again on every `add_element` call.

## How it works

```
LLM → excalidraw-mcp (own volume) → export_diagram()/export_png() → /exchange → browser (download)
```

A Python service (same basic pattern as [android-mcp](android.md) and the code sandbox) that manages `.excalidraw` JSON files in its own Docker volume. `export_diagram()`/`export_png()` copy into the same shared volume used by [Exchange Bridge](exchange-bridge.md) and `android-mcp` — no extra credentials needed, it's just a copy target.

For `export_png()`, the image additionally bundles Excalidraw's own image renderer (built into a single file with esbuild once at image-build time, no internet needed at runtime) plus a headless Chromium (Playwright) — so this image is noticeably larger than the other MCP tools in this stack, similar to [android-mcp](android.md).

## Configuration

The service is optional. If you don't need diagrams, remove `excalidraw-mcp` from `docker-compose.rocm.yml` entirely (then also remove the `excalidraw` entry from `librechat/librechat.yaml` and `mcpo/config.template.json`).

Troubleshooting works like any other MCP tool: `./scripts/diagnose-mcp.sh`.
