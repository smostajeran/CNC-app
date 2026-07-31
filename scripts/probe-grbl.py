#!/usr/bin/env python3
"""Probe a GRBL board over USB serial: capture $I and $$.

Usage:
  python3 scripts/probe-grbl.py              # auto-pick a candidate port
  python3 scripts/probe-grbl.py /dev/cu.usbserial-XXXX
  python3 scripts/probe-grbl.py --baud 115200

Writes docs/hardware/grbl-probe.md and prints a summary.
"""

from __future__ import annotations

import argparse
import glob
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import serial  # type: ignore
except ImportError:
    print("pyserial is required: python3 -m pip install pyserial", file=sys.stderr)
    sys.exit(2)

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "docs" / "hardware" / "grbl-probe.md"

CANDIDATE_GLOBS = (
    "/dev/cu.usbserial*",
    "/dev/cu.usbmodem*",
    "/dev/cu.wchusbserial*",
    "/dev/cu.SLAB_USBtoUART*",
    "/dev/cu.CH340*",
    "/dev/tty.usbserial*",
    "/dev/tty.usbmodem*",
    "/dev/tty.wchusbserial*",
)


def list_candidate_ports() -> list[str]:
    ports: list[str] = []
    for pattern in CANDIDATE_GLOBS:
        ports.extend(glob.glob(pattern))
    # Prefer cu.* on macOS
    ports = sorted(set(ports), key=lambda p: (0 if "/cu." in p else 1, p))
    return ports


def read_until_idle(ser: serial.Serial, idle_s: float = 0.35, max_s: float = 4.0) -> str:
    chunks: list[bytes] = []
    deadline = time.monotonic() + max_s
    last_data = time.monotonic()
    while time.monotonic() < deadline:
        waiting = ser.in_waiting
        if waiting:
            chunks.append(ser.read(waiting))
            last_data = time.monotonic()
        elif chunks and (time.monotonic() - last_data) >= idle_s:
            break
        else:
            time.sleep(0.05)
    return b"".join(chunks).decode("utf-8", errors="replace")


def probe(port: str, baud: int) -> dict[str, str]:
    result: dict[str, str] = {
        "port": port,
        "baud": str(baud),
        "banner": "",
        "build_info": "",
        "settings": "",
        "error": "",
    }
    try:
        with serial.Serial(port, baudrate=baud, timeout=0.2) as ser:
            time.sleep(2.0)  # Nano auto-reset
            ser.reset_input_buffer()
            # Soft-reset wakes GRBL status
            ser.write(b"\x18")
            time.sleep(0.5)
            result["banner"] = read_until_idle(ser).strip()

            ser.write(b"$I\n")
            result["build_info"] = read_until_idle(ser).strip()

            ser.write(b"$$\n")
            result["settings"] = read_until_idle(ser, max_s=6.0).strip()
    except Exception as exc:  # noqa: BLE001 — surface any serial failure to the report
        result["error"] = f"{type(exc).__name__}: {exc}"
    return result


def extract_travel(settings: str) -> dict[str, str]:
    travel: dict[str, str] = {}
    for line in settings.splitlines():
        line = line.strip()
        if line.startswith("$130="):
            travel["x_max_mm"] = line.split("=", 1)[1].split(" ", 1)[0]
        elif line.startswith("$131="):
            travel["y_max_mm"] = line.split("=", 1)[1].split(" ", 1)[0]
        elif line.startswith("$132="):
            travel["z_max_mm"] = line.split("=", 1)[1].split(" ", 1)[0]
        elif line.startswith("$100="):
            travel["x_steps_mm"] = line.split("=", 1)[1].split(" ", 1)[0]
        elif line.startswith("$101="):
            travel["y_steps_mm"] = line.split("=", 1)[1].split(" ", 1)[0]
        elif line.startswith("$102="):
            travel["z_steps_mm"] = line.split("=", 1)[1].split(" ", 1)[0]
    return travel


def write_report(
    *,
    status: str,
    candidates: list[str],
    probed: dict[str, str] | None,
) -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines = [
        "# GRBL live probe",
        "",
        f"**Status:** {status}",
        f"**Probed at:** {now}",
        "",
        "## Host scan",
        "",
        f"Candidate serial ports: `{candidates if candidates else 'none'}`",
        "",
    ]

    if probed is None:
        lines += [
            "## Result",
            "",
            "No Bachin / Arduino Nano USB serial device was present.",
            "Connect the TA-4 with its USB cable (power adapter on), then re-run:",
            "",
            "```bash",
            "python3 -m pip install pyserial",
            "python3 scripts/probe-grbl.py",
            "```",
            "",
            "Expected when connected: GRBL banner, `$I` build info, and `$$` settings",
            "(baud typically **115200**; travel near **390 × 200 mm** if soft limits match the frame).",
            "",
        ]
    else:
        travel = extract_travel(probed.get("settings", ""))
        lines += [
            "## Connection",
            "",
            f"- Port: `{probed['port']}`",
            f"- Baud: `{probed['baud']}`",
            "",
        ]
        if probed.get("error"):
            lines += ["## Error", "", f"```\n{probed['error']}\n```", ""]
        lines += [
            "## Banner / soft-reset",
            "",
            f"```\n{probed.get('banner') or '(empty)'}\n```",
            "",
            "## `$I` (build info)",
            "",
            f"```\n{probed.get('build_info') or '(empty)'}\n```",
            "",
            "## `$$` (settings)",
            "",
            f"```\n{probed.get('settings') or '(empty)'}\n```",
            "",
            "## Parsed motion params",
            "",
        ]
        if travel:
            for key, val in travel.items():
                lines.append(f"- `{key}`: {val}")
        else:
            lines.append("- (could not parse `$100`–`$102` / `$130`–`$132`)")
        lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe GRBL $$ / $I on USB serial")
    parser.add_argument("port", nargs="?", help="Serial port (default: auto)")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    candidates = list_candidate_ports()
    port = args.port
    if not port:
        if not candidates:
            write_report(status="not connected — no USB serial candidate", candidates=[], probed=None)
            print("No USB serial candidate ports found. Plug in the TA-4 and retry.", file=sys.stderr)
            return 1
        port = candidates[0]
        print(f"Auto-selected {port}")

    probed = probe(port, args.baud)
    ok = bool(probed.get("settings") or probed.get("build_info") or probed.get("banner")) and not probed.get(
        "error"
    )
    status = "ok — captured GRBL response" if ok else "attempted — no valid GRBL response"
    write_report(status=status, candidates=candidates, probed=probed)
    if probed.get("error"):
        print(probed["error"], file=sys.stderr)
        return 1
    if not ok:
        print("Connected but did not receive GRBL $$ / $I. Try another baud or port.", file=sys.stderr)
        return 1
    print(probed.get("build_info") or probed.get("banner"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
