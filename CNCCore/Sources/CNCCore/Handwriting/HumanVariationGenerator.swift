import Foundation

/// Smooth, seeded geometric imperfections — not per-point white noise.
public struct HumanVariationConfig: Equatable, Sendable {
    public var enabled: Bool
    public var positionAmplitudeMm: Double
    public var baselineDriftMmPerMm: Double
    public var scaleJitter: Double
    public var slantJitterRad: Double
    public var seed: UInt64

    public static let neat = HumanVariationConfig(
        enabled: true,
        positionAmplitudeMm: 0.12,
        baselineDriftMmPerMm: 0.002,
        scaleJitter: 0.02,
        slantJitterRad: 0.015,
        seed: 1
    )

    public static let messy = HumanVariationConfig(
        enabled: true,
        positionAmplitudeMm: 0.32,
        baselineDriftMmPerMm: 0.006,
        scaleJitter: 0.05,
        slantJitterRad: 0.04,
        seed: 1
    )

    public static let off = HumanVariationConfig(
        enabled: false,
        positionAmplitudeMm: 0,
        baselineDriftMmPerMm: 0,
        scaleJitter: 0,
        slantJitterRad: 0,
        seed: 0
    )

    public init(
        enabled: Bool,
        positionAmplitudeMm: Double,
        baselineDriftMmPerMm: Double,
        scaleJitter: Double,
        slantJitterRad: Double,
        seed: UInt64
    ) {
        self.enabled = enabled
        self.positionAmplitudeMm = positionAmplitudeMm
        self.baselineDriftMmPerMm = baselineDriftMmPerMm
        self.scaleJitter = scaleJitter
        self.slantJitterRad = slantJitterRad
        self.seed = seed
    }
}

public enum HumanVariationGenerator {
    /// Apply smooth positional deviation + mild baseline drift along each stroke.
    public static func vary(_ job: PlotJob, config: HumanVariationConfig) -> PlotJob {
        guard config.enabled, config.positionAmplitudeMm > 0 else { return job }
        var rng = SeededRNG(seed: config.seed)
        var out: [PlotCommand] = []
        out.reserveCapacity(job.commands.count)

        var strokeIndex = 0
        var inStroke = false
        var strokePoints: [PlotPoint] = []
        var pendingMove: PlotPoint?

        func emitStroke(_ pts: [PlotPoint]) {
            guard pts.count >= 2 else { return }
            let varied = varyStroke(pts, strokeIndex: strokeIndex, config: config, rng: &rng)
            strokeIndex += 1
            for (i, p) in varied.enumerated() {
                out.append(i == 0 ? .move(p) : .line(p))
            }
        }

        for cmd in job.commands {
            switch cmd {
            case .move(let p):
                if inStroke {
                    emitStroke(strokePoints)
                    strokePoints = []
                    inStroke = false
                }
                pendingMove = p
            case .line(let p):
                if !inStroke {
                    if let m = pendingMove {
                        strokePoints = [m, p]
                    } else {
                        strokePoints = [p]
                    }
                    pendingMove = nil
                    inStroke = true
                } else {
                    strokePoints.append(p)
                }
            case .penChange(let label):
                if inStroke {
                    emitStroke(strokePoints)
                    strokePoints = []
                    inStroke = false
                }
                if let m = pendingMove {
                    out.append(.move(m))
                    pendingMove = nil
                }
                out.append(.penChange(label))
            }
        }
        if inStroke {
            emitStroke(strokePoints)
        } else if let m = pendingMove {
            out.append(.move(m))
        }
        return PlotJob(commands: out)
    }

    private static func varyStroke(
        _ pts: [PlotPoint],
        strokeIndex: Int,
        config: HumanVariationConfig,
        rng: inout SeededRNG
    ) -> [PlotPoint] {
        let amp = config.positionAmplitudeMm
        // One smooth offset target mid-stroke; interpolate with smoothstep along s.
        let ox = (rng.nextDouble() * 2 - 1) * amp
        let oy = (rng.nextDouble() * 2 - 1) * amp
        let ox2 = (rng.nextDouble() * 2 - 1) * amp
        let oy2 = (rng.nextDouble() * 2 - 1) * amp
        var length = 0.0
        for i in 1..<pts.count {
            length += HandwritingMath.distance(pts[i - 1], pts[i])
        }
        var s = 0.0
        var out: [PlotPoint] = []
        out.reserveCapacity(pts.count)
        for i in pts.indices {
            if i > 0 { s += HandwritingMath.distance(pts[i - 1], pts[i]) }
            let t = length > 1e-6 ? s / length : 0
            let w = HandwritingMath.smoothstep(t)
            let dx = HandwritingMath.lerp(ox, ox2, w)
            let dy = HandwritingMath.lerp(oy, oy2, w) + config.baselineDriftMmPerMm * s
                * (strokeIndex % 2 == 0 ? 1 : -1)
            out.append(PlotPoint(x: pts[i].x + dx, y: pts[i].y + dy, pressure: pts[i].pressure))
        }
        return out
    }
}

/// Tiny deterministic RNG (xorshift64*) for reproducible variation.
public struct SeededRNG: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    public mutating func nextDouble() -> Double {
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }

    public mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextDouble()
    }
}
