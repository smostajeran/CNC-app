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
    /// Group strokes into horizontal *text lines* and alternate LTR / RTL (serpentine).
    /// RTL lines reverse visit order and each stroke’s vertex order (not an X-mirror).
    case serpentineRows
    /// Group into horizontal lines and always plot left → right (no RTL passes).
    case rowsLeftToRight
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

    /// Default for Quill writing: left-to-right per text line.
    /// Serpentine RTL passes reverse stroke *visit* order and look like flipped letters
    /// on the machine even when final ink geometry is upright — keep that opt-in.
    public static func optimize(_ job: PlotJob) -> PlotJob {
        optimize(job, mode: .rowsLeftToRight)
    }

    public static func optimize(_ job: PlotJob, mode: PathOptimizeMode) -> PlotJob {
        // Preserve `.penChange` barriers (pause before/after, multi-pen). Optimize each
        // segment independently so M0 markers are never dropped by jobFromPaths.
        var chunks: [[PlotCommand]] = [[]]
        var barriers: [String] = []
        for cmd in job.commands {
            if case .penChange(let label) = cmd {
                barriers.append(label)
                chunks.append([])
            } else {
                chunks[chunks.count - 1].append(cmd)
            }
        }
        var merged: [PlotCommand] = []
        for (idx, chunk) in chunks.enumerated() {
            if idx > 0 {
                merged.append(.penChange(barriers[idx - 1]))
            }
            guard !chunk.isEmpty else { continue }
            let optimizedChunk = optimizeChunk(PlotJob(commands: chunk), mode: mode)
            merged.append(contentsOf: optimizedChunk.commands)
        }
        return PlotJob(commands: merged)
    }

    private static func optimizeChunk(_ job: PlotJob, mode: PathOptimizeMode) -> PlotJob {
        switch mode {
        case .nearestNeighbor(let allowReverse):
            return nearestNeighbor(job, allowReverse: allowReverse)
        case .serpentineRows:
            return orderByRows(job, serpentine: true)
        case .rowsLeftToRight:
            return orderByRows(job, serpentine: false)
        }
    }

    /// How many horizontal lines the row clusterer finds (for tests / diagnostics).
    public static func rowCount(for job: PlotJob) -> Int {
        clusterRows(extractDrawPaths(from: job)).count
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

    private struct RowItem {
        var path: PathSegment
        var y: Double
        var xMin: Double
        var xMax: Double
        var height: Double
    }

    /// Plot line-by-line (by Y). When `serpentine` is true, odd lines are visited RTL with
    /// each stroke vertex-reversed so absolute ink stays upright and left-to-right readable.
    ///
    /// Row breaks use adaptive Y gaps so strokes that belong to the *same* text line
    /// (e.g. a T’s top bar vs stem) are not split into separate LTR/RTL bands — that
    /// fixed-4 mm banding made every other pass through a glyph line look backwards.
    private static func orderByRows(_ job: PlotJob, serpentine: Bool) -> PlotJob {
        let paths = extractDrawPaths(from: job)
        guard paths.count > 1 else { return job }

        let rows = clusterRows(paths)
        guard rows.count >= 1 else { return job }

        var ordered: [PathSegment] = []
        ordered.reserveCapacity(paths.count)
        for (rowIndex, row) in rows.enumerated() {
            let rightToLeft = serpentine && rowIndex % 2 == 1
            if rightToLeft {
                // Visit rightmost stroke first; reverse vertices so the pen enters from the
                // right while each letter’s geometry stays unmirrored.
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

    /// Cluster strokes into horizontal text lines (top → bottom in machine Y-up space).
    private static func clusterRows(_ paths: [PathSegment]) -> [[RowItem]] {
        var items: [RowItem] = paths.compactMap { path in
            guard !path.points.isEmpty else { return nil }
            let ys = path.points.map(\.y)
            let xs = path.points.map(\.x)
            let yMin = ys.min()!
            let yMax = ys.max()!
            let y = ys.reduce(0, +) / Double(ys.count)
            return RowItem(
                path: path,
                y: y,
                xMin: xs.min()!,
                xMax: xs.max()!,
                height: yMax - yMin
            )
        }
        guard !items.isEmpty else { return [] }

        // Top of page first (larger Y).
        items.sort { $0.y > $1.y }

        // Break only on gaps large enough to be inter-line, not intra-glyph.
        // Tall stick glyphs (~font size) have stroke centroids several mm apart;
        // a fixed 4 mm tolerance was shredding each line into LTR/RTL bands.
        let maxHeight = items.map(\.height).max() ?? 0
        let breakGap = max(maxHeight * 0.45, 6.0)

        var rows: [[RowItem]] = []
        for item in items {
            if var last = rows.last {
                let rowMeanY = last.map(\.y).reduce(0, +) / Double(last.count)
                let gapFromPrev = abs(item.y - last.last!.y)
                let gapFromMean = abs(item.y - rowMeanY)
                // Same line if close to the previous stroke and to the row’s running mean.
                if gapFromPrev <= breakGap && gapFromMean <= breakGap * 1.25 {
                    last.append(item)
                    rows[rows.count - 1] = last
                    continue
                }
            }
            rows.append([item])
        }
        return rows
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
