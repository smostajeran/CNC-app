import Foundation

public enum HandwritingMath {
    @inlinable
    public static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    @inlinable
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Hermite smoothstep on `t` in 0…1.
    @inlinable
    public static func smoothstep(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x * x * (3 - 2 * x)
    }

    /// Smootherstep (Ken Perlin).
    @inlinable
    public static func smootherstep(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    @inlinable
    public static func distance(_ a: PlotPoint, _ b: PlotPoint) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// Signed turn angle (radians) at vertex b given a→b→c.
    public static func turnAngle(a: PlotPoint, b: PlotPoint, c: PlotPoint) -> Double {
        let v1x = b.x - a.x, v1y = b.y - a.y
        let v2x = c.x - b.x, v2y = c.y - b.y
        let n1 = hypot(v1x, v1y), n2 = hypot(v2x, v2y)
        guard n1 > 1e-9, n2 > 1e-9 else { return 0 }
        let cross = v1x * v2y - v1y * v2x
        let dot = v1x * v2x + v1y * v2y
        return atan2(cross, dot)
    }

    /// Approximate curvature magnitude from three points (1/mm).
    public static func curvature(a: PlotPoint, b: PlotPoint, c: PlotPoint) -> Double {
        let ang = abs(turnAngle(a: a, b: b, c: c))
        let chord = distance(a, c)
        guard chord > 1e-6 else { return 0 }
        return ang / chord
    }
}
