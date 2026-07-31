# CNC-app / TA4Host

Native **macOS** host for the Bachin **T-A4** pen plotter — a modern replacement for the outdated Panda / Bachin Draw software.

## Docs

- [Product goal](docs/PRODUCT_GOAL.md)
- [TA-4 hardware](docs/hardware/bachin-ta4.md)
- [GRBL probe log](docs/hardware/grbl-probe.md)

## Project layout

| Path | Role |
|------|------|
| `CNCCore/` | Swift package — GRBL, serial, streaming, SVG→G-code |
| `TA4Host/` | SwiftUI macOS app |
| `project.yml` | XcodeGen spec → `TA4Host.xcodeproj` |
| `scripts/probe-grbl.py` | CLI probe for `$I` / `$$` |

## Build & run

`project.yml` is in this repo root (`Documents/CNC-app`), not your home folder. Always run XcodeGen from here:

```bash
cd /Users/sasanmostajeran/Documents/CNC-app
brew install xcodegen   # if needed
./scripts/generate-xcode.sh
open TA4Host.xcodeproj
```

Or:

```bash
cd /Users/sasanmostajeran/Documents/CNC-app
xcodegen generate --spec project.yml
open TA4Host.xcodeproj
```

CLI checks:

```bash
cd /Users/sasanmostajeran/Documents/CNC-app
swift test --package-path CNCCore
xcodegen generate --spec project.yml
xcodebuild -scheme TA4Host -configuration Debug build
```

## Probe the machine (USB)

```bash
python3 -m pip install -r requirements.txt
python3 scripts/probe-grbl.py
```

In the app: Connect → Probe writes live settings into the session and console.
