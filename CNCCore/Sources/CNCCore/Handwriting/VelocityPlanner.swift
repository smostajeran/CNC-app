import Foundation

public struct VelocitySample: Equatable, Sendable {
    public var speedMmPerSec: Double
    public var feedMmMin: Double
    public var pauseAfterMs: Double
}

public enum VelocityPlanner {
    /// Plan per-vertex speed along an analyzed stroke.
    public static func plan(
        stroke: AnalyzedStroke,
        pen: PenProfile,
        letterIndex: Int = 0
    ) -> [VelocitySample] {
        let n = stroke.vertices.count
        guard n > 0 else { return [] }
        let baseMmPerSec = pen.nominalFeedMmMin / 60.0
        // Mild letter-to-letter tempo drift (±6%).
        let letterScale = 1.0 + 0.06 * sin(Double(letterIndex) * 1.7)
        var samples: [VelocitySample] = []
        samples.reserveCapacity(n)

        for (i, v) in stroke.vertices.enumerated() {
            let t = stroke.lengthMm > 1e-6 ? v.s / stroke.lengthMm : 0
            // Trapezoid-ish: accel 15%, cruise, decel 20%.
            let envelope: Double
            if t < 0.15 {
                envelope = HandwritingMath.smoothstep(t / 0.15)
            } else if t > 0.80 {
                envelope = HandwritingMath.smoothstep((1 - t) / 0.20)
            } else {
                envelope = 1
            }
            // Slow near high curvature.
            let curveFactor = 1.0 / (1.0 + v.curvature * 8.0)
            var speed = baseMmPerSec * letterScale * HandwritingMath.lerp(0.35, 1.0, envelope) * curveFactor
            switch stroke.kind {
            case .dot, .shortMark:
                speed *= 0.55
            case .connecting, .upstroke:
                speed *= 1.15
            case .downstroke:
                speed *= 0.9
            case .terminal:
                speed *= 0.85
            case .main:
                break
            }
            speed = HandwritingMath.clamp(speed, baseMmPerSec * 0.2, baseMmPerSec * 1.6)
            let pause: Double
            if i + 1 == n {
                switch stroke.kind {
                case .dot: pause = 35
                case .shortMark: pause = 25
                case .terminal: pause = 40
                default: pause = 12
                }
            } else if v.curvature > 0.35 {
                pause = 8
            } else {
                pause = 0
            }
            samples.append(VelocitySample(
                speedMmPerSec: speed,
                feedMmMin: speed * 60,
                pauseAfterMs: pause
            ))
        }
        return samples
    }

    public static func wordPauseMs(seed: UInt64, wordIndex: Int) -> Double {
        var rng = SeededRNG(seed: seed ^ UInt64(wordIndex) &* 1_103_515_245)
        return rng.nextDouble(in: 40...120)
    }

    public static func letterPauseMs(seed: UInt64, letterIndex: Int) -> Double {
        var rng = SeededRNG(seed: seed ^ UInt64(letterIndex) &* 97_351)
        return rng.nextDouble(in: 15...60)
    }
}
