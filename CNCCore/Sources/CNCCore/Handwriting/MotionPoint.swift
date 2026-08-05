import Foundation

public struct MotionPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var time: Double
    public var speed: Double
    public var pressure: Double
    public var penDown: Bool
    public var strokeType: StrokeKind
    public var feedMmMin: Double

    public init(
        x: Double,
        y: Double,
        time: Double,
        speed: Double,
        pressure: Double,
        penDown: Bool,
        strokeType: StrokeKind,
        feedMmMin: Double
    ) {
        self.x = x
        self.y = y
        self.time = time
        self.speed = speed
        self.pressure = pressure
        self.penDown = penDown
        self.strokeType = strokeType
        self.feedMmMin = feedMmMin
    }
}

public enum MotionPointGenerator {
    public static func generate(
        strokes: [AnalyzedStroke],
        pen: PenProfile,
        seed: UInt64,
        wordBreakEvery: Int = 5
    ) -> [MotionPoint] {
        var points: [MotionPoint] = []
        var time = 0.0
        for (si, stroke) in strokes.enumerated() {
            let velocities = VelocityPlanner.plan(stroke: stroke, pen: pen, letterIndex: si)
            let rawP = PressurePlanner.plan(
                stroke: stroke,
                pen: pen,
                velocities: velocities,
                seed: seed &+ UInt64(si) &* 17
            )
            let arcs = stroke.vertices.map(\.s)
            let filtered = ServoPressureFilter.filter(
                pressures: rawP,
                arcLengths: arcs,
                pen: pen
            )

            for i in stroke.vertices.indices {
                let v = stroke.vertices[i]
                let vel = i < velocities.count ? velocities[i] : VelocitySample(
                    speedMmPerSec: pen.nominalFeedMmMin / 60,
                    feedMmMin: pen.nominalFeedMmMin,
                    pauseAfterMs: 0
                )
                let p = i < filtered.count ? filtered[i] : pen.basePressure
                if i > 0 {
                    let ds = max(v.s - stroke.vertices[i - 1].s, 0)
                    time += ds / max(vel.speedMmPerSec, 1e-3)
                }
                points.append(MotionPoint(
                    x: v.point.x,
                    y: v.point.y,
                    time: time,
                    speed: vel.speedMmPerSec,
                    pressure: p,
                    penDown: true,
                    strokeType: stroke.kind,
                    feedMmMin: vel.feedMmMin
                ))
                time += vel.pauseAfterMs / 1000
            }

            // Inter-stroke / letter / word pauses (pen up time advances clock only).
            if si + 1 < strokes.count {
                if wordBreakEvery > 0, (si + 1) % wordBreakEvery == 0 {
                    time += VelocityPlanner.wordPauseMs(seed: seed, wordIndex: si) / 1000
                } else {
                    time += VelocityPlanner.letterPauseMs(seed: seed, letterIndex: si) / 1000
                }
            }
        }
        return points
    }
}
