# TA-4 firmware verification checklist

Before trusting jog, SVG jobs, or settings, confirm what GRBL build is on the Nano.

## Expected (OEM T-A4)

| Check | Expected |
|-------|----------|
| Controller | ATmega328P Nano on Bachin board |
| OEM hex | `nano_328p_ta4` (Bachin Nano flash tool) |
| Dialect | GRBL **1.1** family (`1.1f` commonly cited) |
| Baud | **115200** |
| Soft reset banner | Contains `Grbl 1.1` |
| `$I` | Contains `[VER:1.1…]` (exact letter may vary) |
| Motion | `$J=` jog works; pen Z is a short axis, not laser `$32=1` as primary mode |

## Known problem builds

| Signal | Risk |
|--------|------|
| `$I` / banner shows **`1.1z`** | Vendor custom; third-party senders may connect and read `$$` but **jog fails** ([LaserGRBL #543](https://github.com/arkypita/LaserGRBL/issues/543)) |
| No banner / no `$I` | Wrong baud, dead USB-UART, or wiped firmware |
| `$32=1` (laser mode) with pen machine | Wrong machine profile; turn laser mode off for pen plotting unless you intend laser |
| `$130`/`$131` far from ~390×200 | Soft limits / travel not matched to frame — calibrate after probe |

## How to probe (this Mac)

1. Power the TA-4 with the **12V** adapter (blue switch / board POWER LED on).
2. Connect **USB data** cable.
3. Run:

```bash
cd /Users/sasanmostajeran/Documents/CNC-app
python3 -m pip install -r requirements.txt
python3 scripts/probe-grbl.py
```

4. Or in **Quill**: Setup → Connect → **Check machine** — firmware assessment appears on Setup.
5. Review [`grbl-probe.md`](./grbl-probe.md) (auto-written by the CLI).

## Pass / fail for Quill

**Pass** if:

- Banner or `$I` shows GRBL 1.1.x
- Not stuck in Alarm after `$X`
- A 10 mm jog changes MPos with 12V on
- Travel settings are plausible (or you accept and tune `$130`/`$131`)

**Investigate / reflash** if:

- Version letter is exotic (`1.1z`) and `$J=` does nothing while `$$` works
- Firmware does not respond at 115200 on any candidate port
- Wrong hex was flashed (use Bachin `nano_328p_ta4` or a known-good GRBL 1.1.f/g and re-tune `$` settings)

## Reflash (only if needed)

OEM: [Bachin Arduino Nano Flash Tool](https://www.bachinmaker.com/wikien/doku.php?id=bachin_arduino_nano_flash_tool) + **`nano_328p_ta4.zip`**.

Warning: wrong hex will not brick the Nano permanently, but the machine will misbehave until the correct image and `$` settings are restored. Prefer probing first; do not reflash “just in case.”

## Current host status

See live result in [`grbl-probe.md`](./grbl-probe.md). If that file says **not connected**, plug in the machine and re-run the probe before changing firmware.
