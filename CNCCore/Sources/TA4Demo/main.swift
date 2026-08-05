import Foundation
import CNCCore

print("Quill core demo (Linux/macOS CLI)")
print(String(repeating: "=", count: 48))

// 1) Pressure mapping
var machine = MachineProfile.ta4
machine.pressureMinZ = 1.5
machine.pressureMaxZ = 0
machine.clampPressureRange()
print("\n[1] Pressure → Z")
for p in [0.0, 0.25, 0.5, 0.75, 1.0] {
    print(String(format: "  p=%.2f → Z=%.3f", p, machine.z(forPressure: p)))
}

// 2) Ink handwriting with pressure
print("\n[2] Ink stroke → G-code")
var ink = InkDocument(travelX: machine.travelX, travelY: machine.travelY)
ink.strokes = [
    InkDocument.Stroke(samples: [
        .init(x: 20, y: 100, pressure: 0.2),
        .init(x: 40, y: 120, pressure: 0.5),
        .init(x: 70, y: 110, pressure: 0.95),
        .init(x: 95, y: 90, pressure: 0.4),
    ])
]
let inkGCode = ink.gcode(profile: machine)
print(inkGCode.split(whereSeparator: \.isNewline).prefix(12).joined(separator: "\n"))
print("  … \(inkGCode.split(whereSeparator: \.isNewline).count) lines total")

// 3) SVG with stroke-width pressure
print("\n[3] SVG stroke-width → pressure → G-code")
let svg = """
<svg viewBox="0 0 100 50">
  <path stroke-width="0.4" d="M5 25 L45 25"/>
  <path stroke-width="2.0" d="M55 25 C70 5 85 45 95 25"/>
</svg>
"""
do {
    let job = try SVGToGCode.plotJob(from: svg, profile: machine, fitToWorkspace: true)
    let pressures = job.commands.compactMap { cmd -> Double? in
        if case .line(let p) = cmd { return p.pressure }
        return nil
    }
    print(String(format: "  line pressures: min=%.2f max=%.2f count=%d",
                 pressures.min() ?? -1, pressures.max() ?? -1, pressures.count))
    let gcode = SVGToGCode.gcode(from: job, profile: machine)
    let zMoves = gcode.split(whereSeparator: \.isNewline).filter { $0.contains("Z") && $0.contains("G1") }
    print("  variable-Z draw lines: \(zMoves.count)")
    for line in zMoves.prefix(6) { print("  \(line)") }
} catch {
    fputs("SVG error: \(error)\n", stderr)
    exit(1)
}

// 4) Character-window streamer dry run
print("\n[4] Streamer character window")
let streamer = GCodeStreamer()
streamer.load(text: inkGCode)
streamer.start()
var sent = 0
var rounds = 0
while streamer.state == .running && rounds < 500 {
    rounds += 1
    var batch = 0
    while let line = streamer.nextLineToSend() {
        sent += 1
        batch += 1
        _ = line
    }
    if batch == 0 && streamer.inFlightCount == 0 { break }
    // Simulate oks for in-flight lines
    let inflight = streamer.inFlightCount
    for _ in 0..<inflight {
        streamer.handleResponse("ok")
    }
}
print("  sent \(sent) lines, state=\(streamer.state), progress=\(String(format: "%.0f%%", streamer.progress * 100))")

print("\nDone. GUI Quill.app still requires macOS + Xcode.")
