import Foundation

/// Helpers for the controlled machine commissioning / calibration wizard.
public enum Commissioning {
    /// Oversized rectangle used to verify soft-limit / preflight rejection.
    public static func oversizeTestGCode(profile: MachineProfile, overshootMm: Double = 40) -> String {
        let x = profile.travelX + overshootMm
        let y = profile.travelY + overshootMm
        return """
        ; Quill oversize safety test — must be rejected before streaming
        G21
        G90
        G0 Z\(fmt(profile.penUpZ))
        G0 X0 Y0
        G0 X\(fmt(x)) Y0
        G0 X\(fmt(x)) Y\(fmt(y))
        G0 X0 Y\(fmt(y))
        G0 X0 Y0
        """
    }

    /// Raised-pen boundary rectangle within safe travel.
    public static func boundaryFrameGCode(profile: MachineProfile, insetMm: Double = 1) -> String {
        let maxX = max(profile.travelX - insetMm, 0)
        let maxY = max(profile.travelY - insetMm, 0)
        return JobPreflight.frameGCode(
            bounds: PlotBounds(minX: insetMm, minY: insetMm, maxX: maxX, maxY: maxY),
            profile: profile
        )
    }

    /// Preflight must reject an oversized job (error severity, not ok to start).
    public static func oversizeIsRejected(profile: MachineProfile) -> Bool {
        let gcode = oversizeTestGCode(profile: profile)
        let report = JobPreflight.assess(
            gcode: gcode,
            profile: profile,
            machineState: "Idle",
            workZeroKnown: true,
            isBusy: false
        )
        return !report.okToStart && report.issues.contains(where: { $0.severity == .error })
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
