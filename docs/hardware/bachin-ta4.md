# BACHIN TA-4 hardware research

## Source

Marketplace listing text (pasteboard):

```
Brand: Domary
BACHIN TA-4 CNC Writing Machine Engraving Robot for Note Table (UK Plug)
```

**Domary** is a reseller/rebrand. The OEM product is **Bachin Draw T-A4** (TA-4 / T-A4) from Huizhou Bachin Electronic Technology Co., Ltd. ([bachinmaker.com](https://bachinmaker.com/?a=view&p=46&r=209)).

## What it is

Desktop **XY pen plotter / writing robot** for notes, handwriting, drawings, and tables. Optional conversion to a small **laser engraver** by swapping the pen module for a Bachin laser kit. Not a milling CNC — belt-driven XY with short Z for pen up/down.

```text
Host PC / Android  --USB serial G-code-->  ATmega328P Nano + GRBL 1.1f
                                              |
                                           A4988 x3
                                      /       |       \
                               42 stepper X   Y   Z (pen lift)
                                                      |
                                                 Pen / optional laser
```

## Specs

| Area | Detail |
|------|--------|
| Work envelope | ~**390 × 200 mm** |
| Frame | Aluminum kit (base + X cross-beam) |
| Motors | **42 stepper** (NEMA 17 class), **A4988**, 16 microstep |
| Z / tool | **Motor pen lift** (Bachin Draw: *Pen Writing Machine with Motor*, same family as ST-2039). Not the T-2039 servo-pen variant |
| Accuracy | Marketing: 0.01 mm; sibling T-2039 wiki: ~0.2–0.3 mm practical |
| Pen | Standard pens/markers; diameter ~**12 mm** (listings often mistranslate as 12 cm) |
| Pen height tip | Pen up ~3–5 mm above paper; software pen-down ~2–5, up/down range 0–8 |
| Power | **DC 12V** adapter; AC **100–240V**; this unit is **UK plug** |
| Host OS (official) | Windows (+ Android handwriting sync app) |
| Files | PNG, JPEG, JPG, BMP, SVG, DXF, G-code |

## Controller / protocol

- **Board:** Bachin laser/drawing control board with replaceable **Arduino Nano (ATmega328P)**
- **Firmware:** **GRBL 1.1f**-compatible; model hex `nano_328p_ta4.zip` via Bachin Nano flash tool
- **Link:** **USB serial** (typical GRBL baud **115200** — confirm with live probe)
- **Host software:** Bachin Draw (official), Candle, Engraver Master; Inkscape for CAM
- Machine type in Bachin Draw: **Pen Writing Machine with Motor**
- Axis invert available if motors run the wrong way
- GRBL `$` params are board-specific — capture with `$$` / `$I` via [`scripts/probe-grbl.py`](../../scripts/probe-grbl.py). Do not assume FAQ sample travel (`$130/$131 = 200`) matches this 390×200 mm frame.

### Official docs

- [T-A4 product / assembly](https://bachinmaker.com/?a=view&p=46&r=209)
- [Bachin Draw user guide](https://bachinmaker.com/?p=71)
- [Sibling writing-bot wiki (GRBL / A4988 / USB)](https://www.bachinmaker.com/wikien/doku.php?id=bachin_writing_bot)
- [Nano flash tool + `nano_328p_ta4` firmware](https://www.bachinmaker.com/wikien/doku.php?id=bachin_arduino_nano_flash_tool)

## Live probe status

See [grbl-probe.md](./grbl-probe.md).

In **TA4Host**: Connect → **Probe $$/$I** applies `$130`/`$131`/`$100`… into the session `MachineProfile`. CLI: `python3 scripts/probe-grbl.py`.
