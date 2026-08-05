import Foundation

public enum GCodeExporter {
    /// Export motion points to GRBL G-code with pressure→Z and variable feed.
    public static func export(
        points: [MotionPoint],
        profile: MachineProfile,
        pen: PenProfile,
        dwellPauses: Bool = true
    ) -> String {
        var lines: [String] = [
            "; Quill handwriting motion",
            "; instrument=\(pen.instrument.rawValue) base=\(String(format: "%.2f", pen.basePressure))",
            "G21",
            "G90",
            "G0 Z\(fmt(profile.penUpZ))",
        ]
        guard !points.isEmpty else {
            return lines.joined(separator: "\n")
        }

        var penDown = false
        var lastPressure: Double?
        var lastTime = points[0].time

        for (idx, mp) in points.enumerated() {
            let pressure = HandwritingMath.clamp(mp.pressure, 0, pen.maxPressureSafety)
            let feed = HandwritingMath.clamp(mp.feedMmMin, 120, profile.jogFeed)
            let z = profile.z(forPressure: pressure)

            if dwellPauses, idx > 0 {
                let dt = mp.time - lastTime
                // Only emit dwell for intentional pauses (pen-up gaps already advance time).
                if !penDown, dt > 0.02 {
                    lines.append(String(format: "G4 P%.3f", min(dt, 0.25)))
                }
            }
            lastTime = mp.time

            if mp.penDown {
                if !penDown {
                    lines.append("G0 X\(fmt(mp.x)) Y\(fmt(mp.y))")
                    lines.append("G1 Z\(fmt(z)) F\(fmt(feed))")
                    penDown = true
                    lastPressure = pressure
                    continue
                }
                if let last = lastPressure,
                   abs(pressure - last) >= MachineProfile.pressureEpsilon {
                    lines.append("G1 X\(fmt(mp.x)) Y\(fmt(mp.y)) Z\(fmt(z)) F\(fmt(feed))")
                    lastPressure = pressure
                } else {
                    lines.append("G1 X\(fmt(mp.x)) Y\(fmt(mp.y)) F\(fmt(feed))")
                }
            } else if penDown {
                lines.append("G0 Z\(fmt(profile.penUpZ))")
                penDown = false
                lastPressure = nil
                lines.append("G0 X\(fmt(mp.x)) Y\(fmt(mp.y))")
            } else {
                lines.append("G0 X\(fmt(mp.x)) Y\(fmt(mp.y))")
            }
        }
        if penDown {
            lines.append("G0 Z\(fmt(profile.penUpZ))")
        }
        lines.append("G0 X0 Y0")
        lines.append("M2")
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
