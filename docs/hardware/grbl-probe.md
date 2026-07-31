# GRBL live probe

**Status:** not connected — no USB serial candidate
**Probed at:** 2026-07-31 13:42:57 UTC

See also: [firmware-checklist.md](./firmware-checklist.md)

## Host scan

Candidate serial ports: `none`

## Firmware assessment

**Verdict:** `unknown` — device not connected.

## Result

No Bachin / Arduino Nano USB serial device was present.
Connect the TA-4 with its USB cable (**12V power on**), then re-run:

```bash
python3 -m pip install pyserial
python3 scripts/probe-grbl.py
```

Expected when connected: GRBL banner, `$I` build info, and `$$` settings
(baud typically **115200**; travel near **390 × 200 mm** if soft limits match the frame).
