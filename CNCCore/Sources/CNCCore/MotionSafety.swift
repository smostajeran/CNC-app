import Foundation

/// Host-side travel envelope checks (machine coordinates), independent of GRBL `$20`.
public enum MotionSafety {
    /// G54/work offset: machine = work + offset.
    public static func workOffset(
        machinePosition mpos: SIMD3<Double>,
        workPosition wpos: SIMD3<Double>
    ) -> (x: Double, y: Double) {
        (mpos.x - wpos.x, mpos.y - wpos.y)
    }

    public static func machineBounds(
        workBounds: PlotBounds,
        offsetX: Double,
        offsetY: Double
    ) -> PlotBounds {
        PlotBounds(
            minX: workBounds.minX + offsetX,
            minY: workBounds.minY + offsetY,
            maxX: workBounds.maxX + offsetX,
            maxY: workBounds.maxY + offsetY
        )
    }

    public static func fitsTravel(
        _ bounds: PlotBounds,
        travelX: Double,
        travelY: Double,
        margin: Double = 0.05
    ) -> Bool {
        bounds.minX >= -margin
            && bounds.minY >= -margin
            && bounds.maxX <= travelX + margin
            && bounds.maxY <= travelY + margin
    }

    /// True when a planned work-space path, placed with the current WCS offset, stays inside travel.
    public static func workPathFitsMachineTravel(
        workBounds: PlotBounds,
        machinePosition: SIMD3<Double>,
        workPosition: SIMD3<Double>,
        travelX: Double,
        travelY: Double,
        margin: Double = 0.05
    ) -> Bool {
        let offset = workOffset(machinePosition: machinePosition, workPosition: workPosition)
        let machine = machineBounds(workBounds: workBounds, offsetX: offset.x, offsetY: offset.y)
        return fitsTravel(machine, travelX: travelX, travelY: travelY, margin: margin)
    }
}
