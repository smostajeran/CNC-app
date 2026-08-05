import Foundation

/// Serializable handwriting strokes with pressure samples (`.ta4ink` JSON).
public struct InkDocument: Equatable, Sendable, Codable {
    public struct Sample: Equatable, Sendable, Codable {
        public var x: Double
        public var y: Double
        public var pressure: Double

        public init(x: Double, y: Double, pressure: Double) {
            self.x = x
            self.y = y
            self.pressure = min(max(pressure, 0), 1)
        }
    }

    public struct Stroke: Equatable, Sendable, Codable {
        public var samples: [Sample]

        public init(samples: [Sample] = []) {
            self.samples = samples
        }
    }

    public var version: Int
    public var travelX: Double
    public var travelY: Double
    public var strokes: [Stroke]

    public init(
        version: Int = 1,
        travelX: Double = MachineProfile.ta4.travelX,
        travelY: Double = MachineProfile.ta4.travelY,
        strokes: [Stroke] = []
    ) {
        self.version = version
        self.travelX = travelX
        self.travelY = travelY
        self.strokes = strokes
    }

    public func plotJob(smoothed: Bool = true) -> PlotJob {
        var commands: [PlotCommand] = []
        for stroke in strokes {
            let samples = smoothed ? InkSmoothing.prepare(stroke.samples) : stroke.samples
            guard let first = samples.first else { continue }
            commands.append(.move(PlotPoint(x: first.x, y: first.y, pressure: first.pressure)))
            for sample in samples.dropFirst() {
                commands.append(.line(PlotPoint(x: sample.x, y: sample.y, pressure: sample.pressure)))
            }
        }
        return PlotJob(commands: commands)
    }

    public func gcode(profile: MachineProfile) -> String {
        SVGToGCode.gcode(from: plotJob(smoothed: true), profile: profile)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func load(from data: Data) throws -> InkDocument {
        try JSONDecoder().decode(InkDocument.self, from: data)
    }

    /// Export a simple SVG with stroke-width proportional to pressure (for Inkscape round-trip).
    public func exportSVG() -> String {
        var paths: [String] = []
        for stroke in strokes {
            guard let first = stroke.samples.first else { continue }
            var d = String(format: "M %.3f %.3f", first.x, travelY - first.y)
            var maxP = first.pressure
            for s in stroke.samples.dropFirst() {
                d += String(format: " L %.3f %.3f", s.x, travelY - s.y)
                maxP = max(maxP, s.pressure)
            }
            let width = 0.2 + maxP * 1.8
            let w = String(format: "%.3f", width)
            paths.append(
                "<path d=\"\(d)\" fill=\"none\" stroke=\"#000\" stroke-width=\"\(w)\"/>"
            )
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(travelX)mm" height="\(travelY)mm"
             viewBox="0 0 \(travelX) \(travelY)">
        \(paths.joined(separator: "\n"))
        </svg>
        """
    }
}

/// Resample / smooth handwriting to limit Z chatter from pressure noise.
public enum InkSmoothing {
    public static let minPointSpacingMm: Double = 0.35
    public static let pressureAlpha: Double = 0.35
    public static let minPressureDelta: Double = 0.04

    public static func prepare(_ samples: [InkDocument.Sample]) -> [InkDocument.Sample] {
        guard samples.count > 2 else { return samples }
        var out: [InkDocument.Sample] = []
        out.reserveCapacity(samples.count)
        var last = samples[0]
        var smoothP = last.pressure
        out.append(last)
        for sample in samples.dropFirst() {
            let dist = hypot(sample.x - last.x, sample.y - last.y)
            smoothP = smoothP * (1 - pressureAlpha) + sample.pressure * pressureAlpha
            let pressureDelta = abs(smoothP - last.pressure)
            if dist < minPointSpacingMm && pressureDelta < minPressureDelta {
                continue
            }
            let next = InkDocument.Sample(x: sample.x, y: sample.y, pressure: smoothP)
            out.append(next)
            last = next
        }
        if let final = samples.last, out.last != final {
            let p = out.last?.pressure ?? final.pressure
            out.append(InkDocument.Sample(x: final.x, y: final.y, pressure: p))
        }
        return out
    }
}

/// Builds strokes from live pointer samples; synthesizes pressure from speed when stylus pressure is unavailable.
public enum InkCapture {
    /// Map pointer speed (mm per event) to pressure: faster → lighter.
    public static func syntheticPressure(distanceMm: Double, dt: TimeInterval) -> Double {
        let speed = dt > 1e-4 ? distanceMm / dt : 0
        // ~0–200 mm/s → pressure 1…0.15
        let t = min(max(speed / 200.0, 0), 1)
        return 1.0 - 0.85 * t
    }
}
