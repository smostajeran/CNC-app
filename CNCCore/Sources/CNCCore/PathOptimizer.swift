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

/// Reorder / reverse path groups to cut pen-up travel.
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

    /// Nearest-neighbor with optional reverse. Keeps pen-change barriers intact when passed as separate jobs.
    public static func optimize(_ job: PlotJob) -> PlotJob {
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
                let dReverse = hypot(e.x - from.x, e.y - from.y)
                if dForward < bestDist {
                    bestDist = dForward
                    bestIdx = i
                    bestReversed = false
                }
                if dReverse < bestDist {
                    bestDist = dReverse
                    bestIdx = i
                    bestReversed = true
                }
            }
            var next = remaining.remove(at: bestIdx)
            if bestReversed { next = next.reversed() }
            ordered.append(next)
            cursor = next
        }

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
