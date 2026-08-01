#!/usr/bin/env python3
"""Stream a G-code file to a GRBL board with ok-paced / character-window flow control.

Usage:
  python3 scripts/send-gcode.py path/to/job.gcode
  python3 scripts/send-gcode.py job.gcode --port /dev/cu.usbserial-XXXX
  python3 scripts/send-gcode.py job.gcode --dry-run
"""

from __future__ import annotations

import argparse
import glob
import sys
import time

RX_BUFFER = 127

CANDIDATE_GLOBS = (
    "/dev/cu.usbserial*",
    "/dev/cu.usbmodem*",
    "/dev/cu.wchusbserial*",
    "/dev/cu.SLAB_USBtoUART*",
    "/dev/cu.CH340*",
)


def list_candidate_ports() -> list[str]:
    ports: list[str] = []
    for pattern in CANDIDATE_GLOBS:
        ports.extend(glob.glob(pattern))
    return sorted(set(ports), key=lambda p: (0 if "/cu." in p else 1, p))


def sanitize(line: str) -> str:
    s = line.strip()
    if ";" in s:
        s = s.split(";", 1)[0].strip()
    if s.startswith("(") and s.endswith(")"):
        return ""
    return s


def load_lines(path: str) -> list[str]:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [ln for ln in (sanitize(raw) for raw in fh) if ln]


def stream(port: str, baud: int, lines: list[str]) -> int:
    try:
        import serial  # type: ignore
    except ImportError:
        print("pyserial is required: python3 -m pip install pyserial", file=sys.stderr)
        return 2

    with serial.Serial(port, baudrate=baud, timeout=0.2) as ser:
        time.sleep(2.0)
        ser.reset_input_buffer()
        ser.write(b"\x18")
        time.sleep(0.4)
        ser.reset_input_buffer()

        idx = 0
        bytes_in_flight = 0
        costs: list[int] = []
        buf = ""

        while idx < len(lines) or costs:
            while idx < len(lines):
                line = lines[idx]
                cost = len(line.encode("utf-8")) + 1
                if bytes_in_flight + cost > RX_BUFFER:
                    break
                ser.write((line + "\n").encode("utf-8"))
                bytes_in_flight += cost
                costs.append(cost)
                idx += 1
                print(f"> {line}")

            waiting = ser.in_waiting
            if waiting:
                buf += ser.read(waiting).decode("utf-8", errors="replace")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    line = line.strip("\r")
                    if line:
                        print(line)
                    if line == "ok" and costs:
                        bytes_in_flight = max(0, bytes_in_flight - costs.pop(0))
                    elif line.startswith("error") or line.startswith("ALARM"):
                        print(f"Fault: {line}", file=sys.stderr)
                        return 1
            else:
                time.sleep(0.01)
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Stream G-code to GRBL")
    parser.add_argument("file", help="G-code file path")
    parser.add_argument("--port", help="Serial port (default: auto)")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--dry-run", action="store_true", help="Print lines only")
    args = parser.parse_args()

    lines = load_lines(args.file)
    if not lines:
        print("No G-code lines to send", file=sys.stderr)
        return 1

    if args.dry_run:
        for line in lines:
            print(line)
        print(f"# {len(lines)} lines", file=sys.stderr)
        return 0

    port = args.port or (list_candidate_ports()[0] if list_candidate_ports() else None)
    if not port:
        print("No USB serial port found", file=sys.stderr)
        return 1
    print(f"Streaming {len(lines)} lines to {port}", file=sys.stderr)
    return stream(port, args.baud, lines)


if __name__ == "__main__":
    sys.exit(main())
