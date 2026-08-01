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

CLI checks:

```bash
swift test --package-path CNCCore
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

## Probe / stream (USB)

```bash
python3 -m pip install -r requirements.txt
python3 scripts/probe-grbl.py
python3 scripts/send-gcode.py path/to/job.gcode
```

In the app: Connect → Probe writes live settings into the session and console.
