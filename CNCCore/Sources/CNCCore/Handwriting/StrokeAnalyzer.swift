import Foundation

public enum StrokeKind: String, Codable, Sendable, Equatable {
    case main
    case connecting
    case terminal
    case dot
    case shortMark
    case downstroke
    case upstroke
}

public struct AnalyzedVertex: Equatable, Sendable {
    public var point: PlotPoint
    public var s: Double
    public var headingRad: Double
    public var curvature: Double
    public var isDownward: Bool
    public var isUpward: Bool
}

public struct AnalyzedStroke: Equatable, Sendable {
    public var kind: StrokeKind
    public var vertices: [AnalyzedVertex]
    public var lengthMm: Double
    public var isPenDown: Bool
}

public enum StrokeAnalyzer {
    /// Split a plot job into pen-down strokes (move starts a stroke; lines extend it).
    public static func analyze(_ job: PlotJob) -> [AnalyzedStroke] {
        var strokes: [AnalyzedStroke] = []
        var pendingMove: PlotPoint?
        var current: [PlotPoint] = []

        func flush() {
            guard current.count >= 2 else {
                current.removeAll(keepingCapacity: true)
                pendingMove = nil
                return
            }
            strokes.append(buildStroke(points: current))
            current.removeAll(keepingCapacity: true)
            pendingMove = nil
        }

        for cmd in job.commands {
            switch cmd {
            case .move(let p):
                flush()
                pendingMove = p
            case .line(let p):
                if current.isEmpty {
                    if let m = pendingMove {
                        current.append(m)
                        pendingMove = nil
                    }
                }
                current.append(p)
            case .penChange:
                flush()
            }
        }
        flush()
        return strokes
    }

    public static func buildStroke(points: [PlotPoint]) -> AnalyzedStroke {
        var verts: [AnalyzedVertex] = []
        verts.reserveCapacity(points.count)
        var s = 0.0
        for i in points.indices {
            if i > 0 {
                s += HandwritingMath.distance(points[i - 1], points[i])
            }
            let heading: Double
            if i + 1 < points.count {
                heading = atan2(points[i + 1].y - points[i].y, points[i + 1].x - points[i].x)
            } else if i > 0 {
                heading = atan2(points[i].y - points[i - 1].y, points[i].x - points[i - 1].x)
            } else {
                heading = 0
            }
            let curv: Double
            if i > 0 && i + 1 < points.count {
                curv = HandwritingMath.curvature(a: points[i - 1], b: points[i], c: points[i + 1])
            } else {
                curv = 0
            }
            let dy: Double
            if i + 1 < points.count {
                dy = points[i + 1].y - points[i].y
            } else if i > 0 {
                dy = points[i].y - points[i - 1].y
            } else {
                dy = 0
            }
            verts.append(AnalyzedVertex(
                point: points[i],
                s: s,
                headingRad: heading,
                curvature: curv,
                isDownward: dy < -0.05,
                isUpward: dy > 0.05
            ))
        }
        let kind = classify(lengthMm: s, vertices: verts)
        return AnalyzedStroke(kind: kind, vertices: verts, lengthMm: s, isPenDown: true)
    }

    public static func classify(lengthMm: Double, vertices: [AnalyzedVertex]) -> StrokeKind {
        if lengthMm < 0.8 || (vertices.count <= 2 && lengthMm < 1.2) {
            return .dot
        }
        if lengthMm < 2.5 {
            return .shortMark
        }
        let down = vertices.filter(\.isDownward).count
        let up = vertices.filter(\.isUpward).count
        let total = max(vertices.count, 1)
        if Double(down) / Double(total) > 0.55 {
            return .downstroke
        }
        if Double(up) / Double(total) > 0.55 && lengthMm < 8 {
            return .connecting
        }
        if Double(up) / Double(total) > 0.55 {
            return .upstroke
        }
        if lengthMm > 6 {
            return .main
        }
        return .terminal
    }
}
