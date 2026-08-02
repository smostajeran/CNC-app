# CNC-app / TA4Host

Native **macOS** host for the Bachin **T-A4** pen plotter — a modern replacement for the outdated Panda / Bachin Draw software.

## Docs

- [Product goal](docs/PRODUCT_GOAL.md)
- [TA-4 hardware](docs/hardware/bachin-ta4.md)
- [GRBL probe log](docs/hardware/grbl-probe.md)

## Project layout

| Path | Role |
|------|------|
| `CNCCore/` | Swift package — GRBL, serial, streaming, SVG→G-code, text, normalizer |
| `TA4Host/` | SwiftUI macOS app |
| `project.yml` | XcodeGen spec → `TA4Host.xcodeproj` |
| `scripts/probe-grbl.py` | CLI probe for `$I` / `$$` |
| `scripts/send-gcode.py` | Headless G-code streamer |

## Build & run

```bash
cd /path/to/CNC-app
brew install xcodegen   # if needed
./scripts/generate-xcode.sh
open TA4Host.xcodeproj
```

CLI checks / build:

```bash
swift test --package-path CNCCore
# Full macOS app (requires Xcode + XcodeGen on a Mac):
./scripts/build-mac.sh
# Or manually:
xcodegen generate --spec project.yml
xcodebuild -scheme TA4Host -configuration Debug build
```

## Inkscape → TA4Host workflow

1. In the app: **Inkscape Template…** (or menu) → save `TA4-workspace.svg` (390×200 mm).
2. Open the template in Inkscape. Set document units to **mm**. Draw on `Pen1` / `Pen2` layers.
3. **Path → Object to Path** before saving.
4. Open the SVG in TA4Host (or drag onto the job pane). Enable **Watch job file** to reload on Save.
5. Different stroke colors / layers insert an `M0` pen-change pause — swap pens, then **Resume**.

Foreign G-code from Candle / plotter Inkscape extensions that uses `M3`/`M5`/`SM03` is rewritten to motor-Z moves on load.

## Handwriting pressure → Z

The TA-4 has no force sensor — pressure is approximated by **motor Z depth** after paper contact.

1. Sidebar **Ink → Show ink canvas**.
2. Draw with a stylus (recommended: Wacom / Sidecar Apple Pencil). Pressure modulates line weight in the canvas and `Z` in G-code.
3. Without a stylus, trackpad/mouse uses a **speed proxy** (faster strokes → lighter pressure).
4. Calibrate **Light Z** / **Hard Z** in Settings; use **Test pressure sweep** on the machine.
5. Soft markers and fountain pens respond better than hard ballpoints; a slightly springy pen holder helps.

SVG paths with varying `stroke-width` also map to pressure when imported. Save ink as `.ta4ink` or export SVG for Inkscape.

## Probe / stream (USB)

```bash
python3 -m pip install -r requirements.txt
python3 scripts/probe-grbl.py
python3 scripts/send-gcode.py path/to/job.gcode
```

In the app: Connect → Probe writes live settings into the session and console.
