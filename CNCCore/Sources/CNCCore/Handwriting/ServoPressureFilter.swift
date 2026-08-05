import Foundation

/// Mechanical inertia proxy: rate-limit then one-pole low-pass along path length.
public enum ServoPressureFilter {
    public static func filter(
        pressures: [Double],
        arcLengths: [Double],
        pen: PenProfile
    ) -> [Double] {
        guard !pressures.isEmpty else { return [] }
        precondition(pressures.count == arcLengths.count)

        var rateLimited: [Double] = []
        rateLimited.reserveCapacity(pressures.count)
        var prev = pressures[0]
        rateLimited.append(prev)
        for i in 1..<pressures.count {
            let ds = max(arcLengths[i] - arcLengths[i - 1], 1e-6)
            let maxDelta = pen.maxPressureDeltaPerMm * ds
            let target = pressures[i]
            let delta = HandwritingMath.clamp(target - prev, -maxDelta, maxDelta)
            prev += delta
            rateLimited.append(prev)
        }

        // Low-pass: α ≈ 1 - exp(-ds / L)
        var filtered: [Double] = []
        filtered.reserveCapacity(rateLimited.count)
        var y = rateLimited[0]
        filtered.append(HandwritingMath.clamp(y, 0, pen.maxPressureSafety))
        for i in 1..<rateLimited.count {
            let ds = max(arcLengths[i] - arcLengths[i - 1], 1e-6)
            let alpha = 1 - exp(-ds / pen.filterLengthMm)
            y += alpha * (rateLimited[i] - y)
            filtered.append(HandwritingMath.clamp(y, pen.minPressure * 0.5, pen.maxPressureSafety))
        }
        return filtered
    }
}
