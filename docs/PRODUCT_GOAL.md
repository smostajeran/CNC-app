# CNC-app product goal

**Target machine:** Domary / Bachin Draw **T-A4** (TA-4) — desktop XY pen plotter with stepper pen-lift Z.

**Problem:** Stock host software (“Panda” / Bachin Draw) is outdated.

**v1 — macOS host app (`Quill`):** native SwiftUI app for **home hobbyists** that replaces the essential Panda workflow over **USB serial GRBL 1.1**:

- Guided **Setup → Move → Calibrate → Draw** shell with plain-language copy (macOS 26 **Liquid Glass** UI)
- Drawing surface calibration: paper size, start corner (work zero), ruler check for steps/mm
- Connect / disconnect, **Check machine** (probe `$$` / `$I`), firmware readiness
- Status, soft-reset, unlock (`$X`), halt (Halt always in toolbar; recovery under **Advanced**)
- Jog X/Y, pen up/down (Z as mm height, not spindle RPM)
- Load G-code and stream with `ok`-based flow control
- Import simple SVG paths → pen G-code (workspace ~**390 × 200 mm**)
- 2D path preview and run progress
- **Advanced:** console, axis invert / `$3`, factory reset

**Shared core:** `CNCCore` Swift package (serial, GRBL protocol, streamer, SVG→G-code, machine profile).

**Out of scope for v1:** handwriting font libraries, Excel/tables, image raster/trace, multi-pen prompts, laser mode, App Store polish.

**Later:** Windows (same UX, serial backend); iOS only after a Wi‑Fi or BLE bridge (stock USB CH340 is not a normal iPhone accessory).
