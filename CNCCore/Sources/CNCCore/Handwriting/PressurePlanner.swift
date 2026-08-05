import Foundation

public enum PressurePlanner {
    /// Compute structured pressure for each vertex of a stroke (pre-filter).
    public static func plan(
        stroke: AnalyzedStroke,
        pen: PenProfile,
        velocities: [VelocitySample],
        seed: UInt64
    ) -> [Double] {
        let n = stroke.vertices.count
        guard n > 0 else { return [] }
        let variation = LowFrequencyVariation.targets(
            lengthMm: max(stroke.lengthMm, 0.1),
            amplitude: pen.humanVariationAmplitude,
            wavelengthMm: pen.humanVariationWavelengthMm,
            seed: seed ^ UInt64(n) &* 0x9E37
        )

        let baseMmPerSec = pen.nominalFeedMmMin / 60.0
        var out: [Double] = []
        out.reserveCapacity(n)

        for i in 0..<n {
            let v = stroke.vertices[i]
            let t = stroke.lengthMm > 1e-6 ? v.s / stroke.lengthMm : 0
            let speed = i < velocities.count ? velocities[i].speedMmPerSec : baseMmPerSec

            // Speed: slow → more pressure, fast → less (bounded).
            let speedRatio = speed / max(baseMmPerSec, 1e-6)
            let speedEffect = HandwritingMath.clamp((1.0 - speedRatio) * 0.08, -0.08, 0.10)

            // Curvature: controlled curves get a small bump.
            let curvatureEffect = HandwritingMath.clamp(v.curvature * 0.15, 0, 0.08)

            // Direction: downward/load-bearing heavier; upward/connecting lighter.
            var directionEffect = 0.0
            if v.isDownward { directionEffect += 0.05 }
            if v.isUpward { directionEffect -= 0.04 }
            // Prefer "down the page" in machine Y-up: negative dy already handled.

            let typeEffect = strokeTypeEffect(stroke.kind)

            let human = variation.value(atS: v.s)

            var raw = pen.basePressure
                + speedEffect
                + curvatureEffect
                + directionEffect
                + typeEffect
                + human

            // Attack / release envelopes (multiply toward min at ends).
            let attack = attackEnvelope(t: t, fraction: pen.attackLengthFraction)
            let release = releaseEnvelope(t: t, fraction: pen.releaseLengthFraction, kind: stroke.kind)
            let env = min(attack, release)
            raw = HandwritingMath.lerp(pen.minPressure, raw, env)

            out.append(HandwritingMath.clamp(raw, pen.minPressure, pen.maxPressureSafety))
        }
        return out
    }

    private static func strokeTypeEffect(_ kind: StrokeKind) -> Double {
        switch kind {
        case .main: return 0.02
        case .downstroke: return 0.05
        case .upstroke: return -0.04
        case .connecting: return -0.06
        case .terminal: return -0.02
        case .dot: return 0.08
        case .shortMark: return 0.03
        }
    }

    private static func attackEnvelope(t: Double, fraction: Double) -> Double {
        guard fraction > 1e-6 else { return 1 }
        if t >= fraction { return 1 }
        return HandwritingMath.smootherstep(t / fraction)
    }

    private static func releaseEnvelope(t: Double, fraction: Double, kind: StrokeKind) -> Double {
        // Stronger release on finishing tails / terminals.
        var f = fraction
        if kind == .terminal || kind == .upstroke { f *= 1.35 }
        if kind == .dot { return 1 } // dots stay firm
        guard f > 1e-6 else { return 1 }
        let u = 1 - t
        if u >= f { return 1 }
        return HandwritingMath.smootherstep(u / f)
    }
}

/// Low-frequency pressure targets every 10–30 mm with smoothstep interpolation.
public struct LowFrequencyVariation: Sendable {
    public var knots: [(s: Double, value: Double)]

    public static func targets(
        lengthMm: Double,
        amplitude: Double,
        wavelengthMm: ClosedRange<Double>,
        seed: UInt64
    ) -> LowFrequencyVariation {
        var rng = SeededRNG(seed: seed)
        var knots: [(Double, Double)] = [(0, (rng.nextDouble() * 2 - 1) * amplitude)]
        var s = 0.0
        while s < lengthMm {
            let step = rng.nextDouble(in: wavelengthMm)
            s += step
            if s >= lengthMm { break }
            knots.append((s, (rng.nextDouble() * 2 - 1) * amplitude))
        }
        knots.append((lengthMm, (rng.nextDouble() * 2 - 1) * amplitude))
        return LowFrequencyVariation(knots: knots)
    }

    public func value(atS s: Double) -> Double {
        guard let first = knots.first, let last = knots.last else { return 0 }
        if s <= first.s { return first.value }
        if s >= last.s { return last.value }
        for i in 0..<(knots.count - 1) {
            let a = knots[i], b = knots[i + 1]
            if s >= a.s && s <= b.s {
                let t = (s - a.s) / max(b.s - a.s, 1e-9)
                return HandwritingMath.lerp(a.value, b.value, HandwritingMath.smoothstep(t))
            }
        }
        return last.value
    }
}
