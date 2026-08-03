import Foundation

/// One evaluated motion / event from modal G-code interpretation.
public struct GCodeSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case rapid
        case feed
        case penChange
        case dwell
        case other
    }

    public var kind: Kind
    public var x: Double
    public var y: Double
    public var z: Double
    public var lineIndex: Int
    public var raw: String
    public var feed: Double?

    public init(kind: Kind, x: Double, y: Double, z: Double, lineIndex: Int, raw: String, feed: Double? = nil) {
        self.kind = kind
        self.x = x
        self.y = y
        self.z = z
        self.lineIndex = lineIndex
        self.raw = raw
        self.feed = feed
    }
}

public struct GCodeParseResult: Equatable, Sendable {
    public var segments: [GCodeSegment]
    public var bounds: PlotBounds
    public var minZ: Double
    public var maxZ: Double
    public var penChangeCount: Int
    public var usedInches: Bool
    public var usedRelative: Bool
    public var unsupported: [String]
    public var estimatedSeconds: Double
    public var plotJob: PlotJob

    public init(
        segments: [GCodeSegment],
        bounds: PlotBounds,
        minZ: Double,
        maxZ: Double,
        penChangeCount: Int,
        usedInches: Bool,
        usedRelative: Bool,
        unsupported: [String],
        estimatedSeconds: Double,
        plotJob: PlotJob
    ) {
        self.segments = segments
        self.bounds = bounds
        self.minZ = minZ
        self.maxZ = maxZ
        self.penChangeCount = penChangeCount
        self.usedInches = usedInches
        self.usedRelative = usedRelative
        self.unsupported = unsupported
        self.estimatedSeconds = estimatedSeconds
        self.plotJob = plotJob
    }
}

/// Modal G-code interpreter for preview, preflight, and bounds checks.
public enum GCodeParser {
    private static let unsupportedPrefixes = [
        "G2", "G02", "G3", "G03", // arcs: tessellated approximately below
        "G5", "G05",
        "G38", "G43", "G49",
        "M3", "M03", "M4", "M04", "M5", "M05", // spindle — usually normalized already
        "M7", "M8", "M9",
        "T",
    ]

    public static func parse(
        _ text: String,
        defaultFeed: Double = 1_500,
        defaultRapid: Double = 3_000
    ) -> GCodeParseResult {
        let lines = GCodeStreamer.normalize(text)
        var absolute = true
        var inches = false
        var x = 0.0, y = 0.0, z = 0.0
        var feed = defaultFeed
        var motion: Int? = nil // 0 rapid, 1 feed
        var segments: [GCodeSegment] = []
        var plotCommands: [PlotCommand] = []
        var unsupported: [String] = []
        var penChanges = 0
        var usedRelative = false
        var usedInches = false
        var minZ = 0.0
        var maxZ = 0.0
        var haveZ = false
        var estSeconds = 0.0
        var penDown = false

        for (idx, raw) in lines.enumerated() {
            let upper = raw.uppercased()
            if isPenChange(upper) {
                penChanges += 1
                segments.append(GCodeSegment(kind: .penChange, x: x, y: y, z: z, lineIndex: idx, raw: raw))
                plotCommands.append(.penChange(raw))
                continue
            }

            if upper.hasPrefix("G90") { absolute = true; continue }
            if upper.hasPrefix("G91") { absolute = false; usedRelative = true; continue }
            if upper.hasPrefix("G20") { inches = true; usedInches = true; continue }
            if upper.hasPrefix("G21") { inches = false; continue }
            if upper.hasPrefix("G17") || upper.hasPrefix("G94") || upper.hasPrefix("G54")
                || upper.hasPrefix("G55") || upper.hasPrefix("G28") || upper.hasPrefix("G30") {
                continue
            }
            if upper.hasPrefix("M2") || upper.hasPrefix("M30") || upper == "M2" || upper.hasPrefix("M02") {
                continue
            }

            if let f = word(upper, "F") { feed = f }

            let g = motionWord(upper)
            if let g {
                if g == 0 || g == 1 { motion = g }
                if g == 2 || g == 3 {
                    // Approximate arc as chord to endpoint (preflight still sees extent).
                    motion = 1
                    unsupported.append("Arc \(raw) approximated as straight chord")
                }
            }

            let hasXYZ = upper.contains("X") || upper.contains("Y") || upper.contains("Z")
            guard hasXYZ, let motion else {
                if looksUnsupported(upper) {
                    unsupported.append(raw)
                }
                continue
            }

            let scale = inches ? 25.4 : 1.0
            let nx = word(upper, "X").map { absolute ? $0 * scale : x + $0 * scale } ?? x
            let ny = word(upper, "Y").map { absolute ? $0 * scale : y + $0 * scale } ?? y
            let nz = word(upper, "Z").map { absolute ? $0 * scale : z + $0 * scale } ?? z

            let dist = hypot(nx - x, ny - y) + abs(nz - z) * 0.25
            let rate = motion == 0 ? defaultRapid : max(feed, 1)
            estSeconds += (dist / rate) * 60.0

            x = nx; y = ny; z = nz
            if !haveZ { minZ = z; maxZ = z; haveZ = true }
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)

            let kind: GCodeSegment.Kind = motion == 0 ? .rapid : .feed
            segments.append(GCodeSegment(kind: kind, x: x, y: y, z: z, lineIndex: idx, raw: raw, feed: feed))

            // Pen heuristic: Z near/below 1 mm ⇒ drawing (matches TA-4 motor lift).
            if word(upper, "Z") != nil {
                penDown = z <= 1.0
            }
            if word(upper, "X") != nil || word(upper, "Y") != nil {
                let p = PlotPoint(x: x, y: y)
                plotCommands.append(penDown && motion == 1 ? .line(p) : .move(p))
            }
        }

        let job = PlotJob(commands: plotCommands)
        return GCodeParseResult(
            segments: segments,
            bounds: job.bounds,
            minZ: haveZ ? minZ : 0,
            maxZ: haveZ ? maxZ : 0,
            penChangeCount: penChanges,
            usedInches: usedInches,
            usedRelative: usedRelative,
            unsupported: Array(Set(unsupported)).sorted(),
            estimatedSeconds: estSeconds,
            plotJob: job
        )
    }

    public static func isPenChange(_ upper: String) -> Bool {
        let t = upper.trimmingCharacters(in: .whitespaces)
        return t == "M0" || t == "M00" || t.hasPrefix("M0 ") || t.hasPrefix("M00 ")
    }

    private static func motionWord(_ upper: String) -> Int? {
        // Match G0/G00/G1/G01/G2/G3 as whole words.
        let pattern = try! NSRegularExpression(pattern: #"\bG0*([0-3])\b"#)
        let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
        guard let match = pattern.firstMatch(in: upper, range: range),
              let r = Range(match.range(at: 1), in: upper) else { return nil }
        return Int(upper[r])
    }

    private static func word(_ upper: String, _ key: String) -> Double? {
        guard let idx = upper.firstIndex(of: Character(key)) else { return nil }
        var i = upper.index(after: idx)
        var num = ""
        while i < upper.endIndex {
            let ch = upper[i]
            if ch.isNumber || ch == "-" || ch == "+" || ch == "." || ch == "e" || ch == "E" {
                num.append(ch)
                i = upper.index(after: i)
            } else {
                break
            }
        }
        return Double(num)
    }

    private static func looksUnsupported(_ upper: String) -> Bool {
        for prefix in unsupportedPrefixes {
            if upper.hasPrefix(prefix) || upper.contains(" \(prefix)") {
                // G0/G1 matched via motion; skip G20/G21 etc.
                if prefix.hasPrefix("G2") && (upper.hasPrefix("G20") || upper.hasPrefix("G21")) {
                    continue
                }
                if prefix == "G2" || prefix == "G02" || prefix == "G3" || prefix == "G03" {
                    return true
                }
                if prefix.hasPrefix("M") || prefix.hasPrefix("T") || prefix.hasPrefix("G3") || prefix.hasPrefix("G4") || prefix.hasPrefix("G5") {
                    return true
                }
            }
        }
        return false
    }
}
