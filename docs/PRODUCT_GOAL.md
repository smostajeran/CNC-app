# CNC-app product goal

**Target machine:** Domary / Bachin Draw **T-A4** (TA-4) — desktop XY pen plotter with stepper pen-lift Z.

**Problem:** Stock host software (“Panda” / Bachin Draw) is outdated and Windows-only.

**v1 — macOS host app (`TA4Host`):** native SwiftUI app that replaces the essential Panda workflow over **USB serial GRBL 1.1**:

- Connect / disconnect, console (`$$`, `$I`)
- Status, soft-reset, unlock (`$X`), halt
- Jog X/Y, pen up/down (Z as mm height, not spindle RPM)
- Load G-code and stream with character-window flow control
- Import SVG paths (including curves) → pen G-code (workspace ~**390 × 200 mm**)
- 2D path preview and run progress

**Shared core:** `CNCCore` Swift package (serial, GRBL protocol, streamer, SVG→G-code, machine profile).

## v1.1 must-haves (forum / OEM pain)

Sourced from Bachin wiki tips, Apple Support Communities, and GRBL issues:

| Need | Status |
|------|--------|
| Native Mac host | Shipped |
| Axis invert + pen Z / feed settings UI | Shipped |
| Work origin set / go | Shipped |
| SVG curves + circle/ellipse | Shipped |
| Single-line text → G-code | Shipped |
| Multi-color SVG pen pause (`M0`) | Shipped |
| Foreign G-code normalize (`M3`/`M5`/`SM03` → Z) | Shipped |
| Inkscape template + file watch reload | Shipped |
| Drag/drop, paste job, Open With, recent files | Shipped |
| Faster GRBL streaming (127-byte window) | Shipped |
| Headless `scripts/send-gcode.py` | Shipped |

## Integrations

- **Inkscape:** export TA-4 workspace SVG; watch open file for Save → reload; layer/stroke colors → pen-change pauses
- **macOS:** drag-drop, paste, document types, recent jobs, `ta4host://` URL scheme
- **Other CAM/senders:** normalize servo pen G-code from Candle / Inkscape extensions
- **CLI:** `scripts/probe-grbl.py`, `scripts/send-gcode.py`

## Deferred

Handwriting font libraries / Bachin Write Android sync, Excel/tables, image raster/trace, DXF, full multi-pen gallery UI, laser mode, Windows host, iOS (needs Wi‑Fi/BLE bridge), App Store polish, Inkscape extension that owns the serial port.
