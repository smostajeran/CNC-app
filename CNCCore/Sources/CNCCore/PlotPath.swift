import Foundation

public struct PlotPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum PlotCommand: Equatable, Sendable {
    case move(PlotPoint) // pen up travel
    case line(PlotPoint) // pen down draw
}

public struct PlotBounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public static let zero = PlotBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public struct PlotJob: Equatable, Sendable {
    public var commands: [PlotCommand]
    public var bounds: PlotBounds

    public init(commands: [PlotCommand], bounds: PlotBounds? = nil) {
        self.commands = commands
        self.bounds = bounds ?? Self.computeBounds(commands)
    }

    public var previewPoints: [PlotPoint] {
        commands.compactMap {
            switch $0 {
            case .move(let p), .line(let p): return p
            }
        }
    }

    private static func computeBounds(_ commands: [PlotCommand]) -> PlotBounds {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var any = false
        for cmd in commands {
            let p: PlotPoint
            switch cmd {
            case .move(let pt), .line(let pt): p = pt
            }
            any = true
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        guard any else { return .zero }
        return PlotBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
