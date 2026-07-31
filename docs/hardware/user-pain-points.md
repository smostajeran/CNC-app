# Bachin TA-4 user complaint research

Recurring problems reported in Bachin OEM docs/wiki/forum, LaserGRBL GitHub, and CH340/macOS communities. Reddit has almost no dedicated TA-4 threads; the strongest signal is OEM FAQ volume plus GRBL sender issues.

## Sources

- [Bachin T-A4 user guide](https://bachinmaker.com/wikien/doku.php?id=bachin_draw_t-a4)
- [TA4 power problem](https://www.bachinmaker.com/wikien/doku.php?id=ta4_power_problem)
- [Motor problems](https://www.bachinmaker.com/wikien/doku.php?id=solve_motor_problem)
- [GRBL default / `$RST=*`](https://bachinmaker.com/index.php?a=view&p=85&r=45)
- [Run Engraver Master on Mac (CH340)](https://www.bachinmaker.com/index.php?a=view&p=85&r=39)
- [LaserGRBL #543 — communication but no control](https://github.com/arkypita/LaserGRBL/issues/543)
- CH340 macOS reports (LightBurn / Longer / Adafruit driver guides)

## Themes

### 1. Software / platform lock-in

Summary:

- Bachin Draw is **Windows-only** (XP/7/8/10); Mac/Linux not supported for the writing-machine path.
- Handwriting companion (**Bachin Write**) is **Android-only**; OEM docs say iPhone is unsupported.
- Stock host feels outdated; users move to Candle, LaserGRBL, Engraver Master, or custom apps.
- Wrong **machine type** in Bachin Draw (*Pen Writing Machine with Motor* vs laser vs servo) causes “connected but wrong behavior.”

#### Deep dive: what the OEM stack actually is

| Layer | Official name | Platforms |
|-------|---------------|-----------|
| Desktop host | **Bachin Draw** (`setup.exe` from bachinmaker) | **Windows XP / 7 / 8 / 10 only** |
| Handwriting capture | **Bachin Write** ([write.apk](http://www.bachinmaker.com/api/write/write.apk)) | **Android only** |
| Optional Mac path | **Engraver Master** for Mac (+ CH340 / XQuartz), not Bachin Draw | Partial Mac, laser-oriented |
| CAM helpers | Inkscape, ArtCAM (OEM “other software”) | Cross-platform tools, not a full host |

OEM wording (T-2039 family docs; same writing ecosystem as T-A4):

> “The software supported with Windows7/8/10 and XP, **can not supported with MAC and Linux**.”

> “Handwriting function currently **only supports Android** system, **i phone is temporarily unable** to use this feature, we will improve this part as soon as possible.”

That “temporary” iPhone gap has remained in public docs for years with no shipped iOS app.

**Note on “Panda”:** OEM pages brand the host as **Bachin Draw**, not “Panda.” “Panda” is likely a reseller bundle name, old installer branding, or informal nickname—same Windows lock-in either way. No reliable OEM page ties “Panda” to Bachin Draw as an official product name.

#### Why lock-in hurts (mechanism)

1. **Desktop must be Windows** for the full writing product (text libraries, Excel/table import claims, handwriting sync, multi-pen SVG prompts).
2. **Custom handwriting needs a second device + Android sideload** (QR → Write app → Synchronization → Generate). No App Store iOS path; TrueType “New Text” instead depends on **Windows Fonts** (`C:\Windows\Fonts`).
3. **One host app serves three toolchains** via a single “Machine type” setting. Wrong choice looks like “connected but broken.”

#### Machine type trap (Bachin Draw menu #9)

Sources: [Bachin Draw user guide](https://bachinmaker.com/?p=71), [ST-2039](https://www.bachinmaker.com/?a=view&p=46&r=211).

| Machine type | Hardware examples | What the host assumes |
|--------------|-------------------|------------------------|
| **Pen Writing Machine with Motor** | **T-A4**, **ST-2039** | Z = stepper pen lift; pen up/down as small Z moves (UI ~0–8; tip pen-down 2–5, pen-up gap ~3–5 mm) |
| **Pen Writing Machine with servo** | **T-2039** (older) | Pen = RC servo commands, not motor Z |
| **Laser Engrave Machine** | Optional laser kit on same board family | Laser/spindle PWM, weak/strong laser, `$32` laser-mode semantics |

T-A4 / ST-2039 docs: select **Pen Writing Machine with Motor**. Mis-set type symptoms:

- Servo mode on a motor-Z machine → pen never lifts correctly / odd Z.
- Laser mode on a pen machine → spindle/laser UI, wrong feeds, laser-mode GRBL expectations.
- Motor mode on T-2039 servo → pen actuation wrong.

This is a **host-side** abstraction over the same GRBL USB board—not a different firmware SKU in the UI.

#### What users migrate to (and lose)

OEM already lists **Candle**, **Engraver Master**, Inkscape as alternatives.

| Alternative | Gains | Loses vs Bachin Draw |
|-------------|-------|----------------------|
| [Candle](https://github.com/Denvi/Candle) | Cross-platform-ish Qt GRBL sender, jog, visualize | No handwriting library, Excel import, Bachin text UX |
| LaserGRBL | Windows laser/plot workflows, active community | Same; some Bachin custom GRBL (`1.1z`) jog quirks |
| Engraver Master | OEM Mac dmg path + firmware update | Not writing-first; CH340 pain on Mac |
| [GRBL-Plotter](https://github.com/svenhb/GRBL-Plotter) | SVG/DXF→G-code, pen-up strategies | Windows-centric; learning curve |
| Custom (**Quill**) | Native Mac, correct pen-motor profile | Must rebuild text/handwriting if desired |

Migration pattern: keep the **GRBL board**, abandon the **Windows + Android writing pipeline**.

#### Quill stance

- Fixed mode: **pen motor Z** (T-A4 / ST-2039 class)—not laser/servo unless added later.
- v1 does **not** depend on Bachin Write QR sync; stock handwriting remaining Android+Windows-only is OEM design, not a Quill bug.
- Setup UI labels the mode explicitly so Bachin Draw “laser type” muscle memory does not recur.

### 2. USB connect / CH340 drivers

- “Software cannot be connected” is a first-class FAQ tip.
- Controllers use USB serial (often **CH340/WCH**). macOS may need Driver Extensions allow-listing; Apple Silicon + newer macOS still report missing `/dev/cu.wchusbserial*`.
- False negatives: charge-only cable, flaky hubs, another app holding the COM port.
- USB can enumerate **even when 12V machine power is off**.

### 3. Connected but no motion

| Symptom | Usual cause |
|---------|-------------|
| PC connects; no XY/Z motion | 12V off / switch LED off / bad PSU |
| `$` works; no jog/G-code motion | Bad GRBL settings (`$RST=*`) or vendor GRBL `1.1z` quirks |
| Motors buzz/jitter, no travel | Motor cable, stuck mechanics, belt too tight, failed A4988 |
| One axis dead | Cable / motor / A4988 (static damage during assembly) |
| Axis only one direction | Bad driver or firmware update needed |
| Mirrored / wrong direction | Invert X/Y in software (`$3` / UI invert) |

### 4. Mechanical / plot quality

- Loose screws; belt too tight or too loose.
- Pen height wrong (OEM tip: pen up ~3–5 mm; pen-down values ~2–5 in Bachin Draw).
- Frame later revised for writing stability ([forum update](https://www.bachinmaker.com/forum/?thread-29.htm=)).

### 5. Firmware / third-party senders

- Vendor GRBL builds (e.g. reported `1.1z`) may connect and answer `$$` but not jog under stock GRBL hosts.
- Reflashing stock GRBL can fix third-party tools but may break Bachin Draw assumptions.

### 6. Feature gaps in stock apps

- No Mac-native writing workflow; no iOS handwriting.
- Image/SVG/text UX tied to Bachin Draw; multi-color only via SVG + pen swaps.

## Troubleshooting flow

1. USB port appears? → else CH340 driver / data cable / hub.
2. Board POWER / 12V on? → else PSU or power switch.
3. Status Idle and jog moves? → else Alarm / unlock / `$RST=*` / firmware.
4. Belt, screws, pen height OK? → else mechanical.
5. Else host app / job / machine profile.

## What Quill addresses

- Native macOS host (**Pen plotter (motor lift) · TA-4** — not spindle/laser/servo).
- Empty-port CH340 troubleshooting copy.
- Warning when USB is up but jog does not move (likely unpowered).
- Axis invert toggles, soft-reset, unlock, careful `$RST=*`.
- Live `$I` / `$$` probe into `MachineProfile`.
- Explicit machine-mode label on Setup (avoids Bachin Draw machine-type confusion).
