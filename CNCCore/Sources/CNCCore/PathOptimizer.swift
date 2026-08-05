import Foundation

public struct JobMetrics: Equatable, Sendable {
    public var drawDistanceMm: Double
    public var travelDistanceMm: Double
    public var penChanges: Int
    public var estimatedSeconds: Double
    public var pathCount: Int

    public init(
        drawDistanceMm: Double = 0,
        travelDistanceMm: Double = 0,
        penChanges: Int = 0,
        estimatedSeconds: Double = 0,
        pathCount: Int = 0
    ) {
        self.drawDistanceMm = drawDistanceMm
        self.travelDistanceMm = travelDistanceMm
        self.penChanges = penChanges
        self.estimatedSeconds = estimatedSeconds
        self.pathCount = pathCount
    }

    public var etaLabel: String {
        if estimatedSeconds < 60 {
            return String(format: "~%.0f s", estimatedSeconds)
        }
        return String(format: "~%.1f min", estimatedSeconds / 60)
    }
}

public struct PathSegment: Equatable, Sendable {
    public var points: [PlotPoint]
    public var isTravel: Bool

    public init(points: [PlotPoint], isTravel: Bool) {
        self.points = points
        self.isTravel = isTravel
    }

    public var lengthMm: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }

    public var start: PlotPoint? { points.first }
    public var end: PlotPoint? { points.last }

    public func reversed() -> PathSegment {
        PathSegment(points: points.reversed(), isTravel: isTravel)
    }
}

public enum PathOptimizeMode: Equatable, Sendable {
    /// Nearest-neighbor; may reverse individual strokes (fine for SVG, unsafe for naïve text).
    case nearestNeighbor(allowReverse: Bool)
    /// Group strokes into horizontal rows and alternate LTR / RTL (serpentine).
    /// RTL rows reverse both visit order and each stroke so ink stays upright and readable.
    case serpentineRows
}

/// Reorder path groups to cut pen-up travel.
public enum PathOptimizer {
    public static func extractDrawPaths(from job: PlotJob) -> [PathSegment] {
        var paths: [PathSegment] = []
        var current: [PlotPoint] = []
        for cmd in job.commands {
            switch cmd {
            case .move(let p):
                if current.count > 1 {
                    paths.append(PathSegment(points: current, isTravel: false))
                }
                current = [p]
            case .line(let p):
                if current.isEmpty {
                    current = [p]
                } else {
                    current.append(p)
                }
            case .penChange:
                if current.count > 1 {
                    paths.append(PathSegment(points: current, isTravel: false))
                }
                current = []
            }
        }
        if current.count > 1 {
            paths.append(PathSegment(points: current, isTravel: false))
        }
        return paths
    }

    /// Default for Quill writing: serpentine rows so alternate lines are not mirrored.
    public static func optimize(_ job: PlotJob) -> PlotJob {
        optimize(job, mode: .serpentineRows)
    }

    public static func optimize(_ job: PlotJob, mode: PathOptimizeMode) -> PlotJob {
        switch mode {
        case .nearestNeighbor(let allowReverse):
            return nearestNeighbor(job, allowReverse: allowReverse)
        case .serpentineRows:
            return serpentineRows(job)
        }
    }

    /// Nearest-neighbor with optional reverse. Keeps pen-change barriers intact when passed as separate jobs.
    private static func nearestNeighbor(_ job: PlotJob, allowReverse: Bool) -> PlotJob {
        let paths = extractDrawPaths(from: job)
        guard paths.count > 1 else { return job }

        var remaining = paths
        var ordered: [PathSegment] = []
        var cursor = remaining.removeFirst()
        ordered.append(cursor)

        while !remaining.isEmpty {
            var bestIdx = 0
            var bestDist = Double.infinity
            var bestReversed = false
            let from = cursor.end!
            for (i, cand) in remaining.enumerated() {
                guard let s = cand.start, let e = cand.end else { continue }
                let dForward = hypot(s.x - from.x, s.y - from.y)
                if dForward < bestDist {
                    bestDist = dForward
                    bestIdx = i
                    bestReversed = false
                }
                if allowReverse {
                    let dReverse = hypot(e.x - from.x, e.y - from.y)
                    if dReverse < bestDist {
                        bestDist = dReverse
                        bestIdx = i
                        bestReversed = true
                    }
                }
            }
            var next = remaining.remove(at: bestIdx)
            if bestReversed { next = next.reversed() }
            ordered.append(next)
            cursor = next
        }

        return jobFromPaths(ordered)
    }

    /// Plot row-by-row (by Y), alternating direction like a typewriter / plough.
    ///
    /// - Even rows: left → right, strokes in original orientation.
    /// - Odd rows: right → left, each stroke reversed so coordinates still draw upright letters.
    ///
    /// This prevents the classic failure mode where the gantry travels RTL but the path data
    /// is still LTR, which makes every other line look mirrored.
    private static func serpentineRows(_ job: PlotJob, rowToleranceMm: Double = 4.0) -> PlotJob {
        let paths = extractDrawPaths(from: job)
        guard paths.count > 1 else { return job }

        struct Item {
            var path: PathSegment
            var y: Double
            var xMin: Double
            var xMax: Double
        }

        var items: [Item] = paths.compactMap { path in
            guard !path.points.isEmpty else { return nil }
            let ys = path.points.map(\.y)
            let xs = path.points.map(\.x)
            let y = ys.reduce(0, +) / Double(ys.count)
            return Item(path: path, y: y, xMin: xs.min()!, xMax: xs.max()!)
        }
        guard items.count > 1 else { return job }

        // Top of page first (larger Y in machine space with Y-up).
        items.sort { $0.y > $1.y }

        var rows: [[Item]] = []
        for item in items {
            if var last = rows.last, let refY = last.first?.y, abs(item.y - refY) <= rowToleranceMm {
                last.append(item)
                rows[rows.count - 1] = last
            } else {
                rows.append([item])
            }
        }

        var ordered: [PathSegment] = []
        ordered.reserveCapacity(items.count)
        for (rowIndex, row) in rows.enumerated() {
            let rightToLeft = rowIndex % 2 == 1
            if rightToLeft {
                // Visit rightmost stroke first; reverse each stroke so pen enters from the right
                // while the ink geometry of each letter stays correct (not mirrored).
                for item in row.sorted(by: { $0.xMax > $1.xMax }) {
                    ordered.append(item.path.reversed())
                }
            } else {
                for item in row.sorted(by: { $0.xMin < $1.xMin }) {
                    ordered.append(item.path)
                }
            }
        }
        return jobFromPaths(ordered)
    }

    private static func jobFromPaths(_ ordered: [PathSegment]) -> PlotJob {
        var commands: [PlotCommand] = []
        for path in ordered {
            guard let first = path.points.first else { continue }
            commands.append(.move(first))
            for p in path.points.dropFirst() {
                commands.append(.line(p))
            }
        }
        return PlotJob(commands: commands)
    }

    public static func metrics(
        for job: PlotJob,
        drawFeed: Double,
        travelFeed: Double,
        penChangeSeconds: Double = 8
    ) -> JobMetrics {
        var draw = 0.0
        var travel = 0.0
        var penChanges = 0
        var paths = 0
        var x = 0.0, y = 0.0
        var have = false
        var penDown = false

        for cmd in job.commands {
            switch cmd {
            case .penChange:
                penChanges += 1
                penDown = false
            case .move(let p):
                if have {
                    travel += hypot(p.x - x, p.y - y)
                }
                x = p.x; y = p.y; have = true
                penDown = false
            case .line(let p):
                if !penDown {
                    paths += 1
                    if have {
                        travel += hypot(p.x - x, p.y - y)
                    }
                    penDown = true
                } else if have {
                    draw += hypot(p.x - x, p.y - y)
                }
                x = p.x; y = p.y; have = true
            }
        }

        let drawFeedSafe = max(drawFeed, 1)
        let travelFeedSafe = max(travelFeed, 1)
        let seconds = (draw / drawFeedSafe + travel / travelFeedSafe) * 60
            + Double(penChanges) * penChangeSeconds
        return JobMetrics(
            drawDistanceMm: draw,
            travelDistanceMm: travel,
            penChanges: penChanges,
            estimatedSeconds: seconds,
            pathCount: paths
        )
    }
}
