import Foundation

/// Helpers for comparing composed preview geometry with parsed G-code XY paths.
public enum PlotGeometry {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Extract pen-down drawing vertices (line endpoints) from a plot job.
    public static func drawingPoints(from job: PlotJob) -> [Point] {
        var points: [Point] = []
        for cmd in job.commands {
            if case .line(let p) = cmd {
                points.append(Point(x: p.x, y: p.y))
            }
        }
        return points
    }

    /// Extract pen-down drawing vertices from modal G-code (G1 moves while Z is down).
    public static func drawingPoints(fromGCode text: String, profile: MachineProfile = .ta4) -> [Point] {
        let parsed = GCodeParser.parse(text, defaultFeed: profile.drawFeed, defaultRapid: profile.jogFeed)
        return drawingPoints(from: parsed.plotJob)
    }

    public static func pointsMatch(
        _ a: [Point],
        _ b: [Point],
        tolerance: Double = 0.05
    ) -> Bool {
        guard a.count == b.count else { return false }
        for (p, q) in zip(a, b) {
            if abs(p.x - q.x) > tolerance || abs(p.y - q.y) > tolerance {
                return false
            }
        }
        return true
    }

    /// Count characters that produce stick-font strokes (excluding whitespace/newlines).
    public static func supportedDrawableCharacterCount(in text: String) -> Int {
        text.filter { ch in
            !ch.isWhitespace && !ch.isNewline && SingleLineText.hasGlyph(for: ch)
        }.count
    }
}
