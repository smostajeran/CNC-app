# Quill (CNC-app)

Native **macOS** host for the Bachin **T-A4** pen plotter — a modern replacement for the outdated Panda / Bachin Draw software.

**Quill is the only app.** An earlier working name `TA4Host` appeared on some branches; that folder/target is retired. Use `Quill/` / `Quill.app` / scheme `Quill`.

## Docs

- [Product goal](docs/PRODUCT_GOAL.md)
- [TA-4 hardware](docs/hardware/bachin-ta4.md)
- [GRBL probe log](docs/hardware/grbl-probe.md)

## Project layout

| Path | Role |
|------|------|
| `CNCCore/` | Swift package — GRBL, serial, streaming, SVG→G-code, text, normalizer |
| `Quill/` | SwiftUI macOS app (**main product**) |
| `project.yml` | XcodeGen spec → `Quill.xcodeproj` |
| `scripts/probe-grbl.py` | CLI probe for `$I` / `$$` |
| `scripts/send-gcode.py` | Headless G-code streamer |

## Build & run

```bash
cd /path/to/CNC-app
brew install xcodegen   # if needed
./scripts/generate-xcode.sh
open Quill.xcodeproj
```

CLI checks / build:

```bash
swift test --package-path CNCCore
# Full macOS app (requires Xcode + XcodeGen on a Mac):
./scripts/build-mac.sh
# Or manually:
xcodegen generate --spec project.yml
xcodebuild -scheme Quill -configuration Debug build
```

## Inkscape → Quill workflow

1. In the app: **Inkscape Template…** (or menu) → save `TA4-workspace.svg` (390×200 mm).
2. Open the template in Inkscape. Set document units to **mm**. Draw on `Pen1` / `Pen2` layers.
3. **Path → Object to Path** before saving.
4. Open the SVG in Quill (or drag onto the job pane). Enable **Watch job file** to reload on Save.
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

## Modes

Quill is organized as **Setup → Compose → Run**:

- **Setup:** connect, probe, set zero, axis wizard, pen Z / pressure
- **Compose:** true-size **Page & Batch Composer** — paper format on the 390×200 mm bed, SVG/text/ink elements, Pen & Layer Studio, path optimisation / ETA, Frame Page, CSV variable-data queue
- **Run:** preflight, Hold / Resume / Stop, pen-change pauses

Diagnostics (console) is optional via the toggle in the top bar. Manual console/jog/probe are locked while a job owns the serial port.

### Page composer quick start

1. **Compose** → choose A4 / A5 / envelope / invitation / custom page size; place paper origin on the bed.
2. Add single-line text, SVG (true size), or handwriting; assign layers to pens (pressure, feed, passes).
3. Review draw/travel distance and ETA; enable **Optimize paths** to cut pen-up travel.
4. **Frame Page** (pen up) then **Preflight & Run**.
5. For mail-merge: put `{name}` in text, **Import CSV…**, preview/skip pages, **Queue next page** (pauses for paper change).

## Axis scale wizard (10 mm = 10 mm)

**Setup → Axis scale wizard…**

1. Put a blank white sheet under the pen; set zero at the start corner; **Probe** first.
2. For X (then Y): mark point 1 → move a known distance (only moves that fit remaining travel) → mark point 2.
3. Measure between the marks with a ruler and enter the real length.
4. Quill writes `$100`/`$101`, reads them back, and rolls back if verification fails.

Longer spans (50–100 mm) give a more accurate scale; the goal is still 1:1 (10 mm commanded → 10 mm on paper).

## Probe / stream (USB)

```bash
python3 -m pip install -r requirements.txt
python3 scripts/probe-grbl.py
python3 scripts/send-gcode.py path/to/job.gcode
```

In the app: Connect → Probe writes live settings into the session and console.
