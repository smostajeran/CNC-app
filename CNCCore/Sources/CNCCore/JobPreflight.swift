import Foundation

public enum PreflightSeverity: String, Equatable, Sendable {
    case error
    case warning
    case info
}

public struct PreflightIssue: Equatable, Sendable, Identifiable {
    public var id: String { "\(severity.rawValue)-\(message)" }
    public var severity: PreflightSeverity
    public var message: String

    public init(severity: PreflightSeverity, message: String) {
        self.severity = severity
        self.message = message
    }
}

public struct JobPreflightReport: Equatable, Sendable {
    public var okToStart: Bool
    public var issues: [PreflightIssue]
    public var parse: GCodeParseResult
    public var estimatedRuntimeLabel: String

    public init(okToStart: Bool, issues: [PreflightIssue], parse: GCodeParseResult) {
        self.okToStart = okToStart
        self.issues = issues
        self.parse = parse
        let secs = max(0, parse.estimatedSeconds)
        if secs < 60 {
            self.estimatedRuntimeLabel = String(format: "~%.0f s", secs)
        } else {
            self.estimatedRuntimeLabel = String(format: "~%.0f min", secs / 60)
        }
    }
}

/// Validates a job against the live machine profile before Start.
public enum JobPreflight {
    public static func assess(
        gcode: String,
        profile: MachineProfile,
        machineState: String? = nil,
        workZeroKnown: Bool = false,
        isBusy: Bool = false,
        /// When true, Start is blocked until X/Y have been homed this connection.
        requireHomed: Bool = false,
        isHomed: Bool = false,
        /// Live GRBL positions for machine-space envelope (soft limits alone are not enough).
        machinePosition: SIMD3<Double>? = nil,
        workPosition: SIMD3<Double>? = nil,
        /// Parsed status with WCO when available — preferred over raw mpos/wpos pair.
        status: GRBLStatus? = nil,
        /// When true, Start requires soft limits enabled on the profile (`$20`).
        requireSoftLimits: Bool = false
    ) -> JobPreflightReport {
        var issues: [PreflightIssue] = []
        let parse = GCodeParser.parse(gcode, defaultFeed: profile.drawFeed, defaultRapid: profile.jogFeed)

        if gcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "No G-code loaded."))
        }

        if isBusy {
            issues.append(.init(severity: .error, message: "Controller is busy with another operation."))
        }

        if requireHomed && !isHomed {
            issues.append(.init(
                severity: .error,
                message: "Home X/Y before Start. Without a valid home the controller can drive past the open end of the bed (no limit switch there)."
            ))
        }

        if requireSoftLimits && !profile.softLimitsEnabled {
            issues.append(.init(
                severity: .error,
                message: "Soft limits ($20) are off. Home X/Y, then enable soft limits in Calibrate before Start so travel cannot exceed $130/$131."
            ))
        }

        if let machineState {
            let s = machineState.lowercased()
            if s.contains("alarm") {
                issues.append(.init(severity: .error, message: "Controller is in Alarm — unlock ($X) before starting."))
            } else if s.contains("hold") {
                issues.append(.init(severity: .warning, message: "Controller is in Hold — Resume or reset before starting."))
            } else if !(s.contains("idle") || s == "unknown") {
                issues.append(.init(
                    severity: .warning,
                    message: "Controller state is \(machineState); prefer Idle before Start."
                ))
            }
        }

        if !workZeroKnown {
            issues.append(.init(
                severity: .warning,
                message: "Work zero has not been set in this session — Compose jobs use bed coordinates from home. Prefer leaving G54 at the homed origin unless you intend a paper-relative offset."
            ))
        }

        if parse.usedInches {
            issues.append(.init(severity: .warning, message: "Job uses inches (G20). Quill assumes mm workspace."))
        }
        if parse.usedRelative {
            issues.append(.init(
                severity: .info,
                message: "Job uses relative mode (G91) in places — preview interprets modally."
            ))
        }

        let b = parse.bounds
        let margin: Double = 0.05

        // Resolve WCS offset before envelope checks. When a live status is supplied it must
        // include WCO (or both MPos and WPos) — never assume the missing vector is zero.
        let offset: (x: Double, y: Double)?
        if let status {
            offset = MotionSafety.workOffset(from: status)
            if offset == nil {
                issues.append(.init(
                    severity: .error,
                    message: "Cannot verify machine-space travel — status lacks WCO (or both MPos and WPos). Request status after Home before Start."
                ))
            }
        } else if let mpos = machinePosition, let wpos = workPosition {
            offset = MotionSafety.workOffset(machinePosition: mpos, workPosition: wpos)
        } else {
            offset = nil
        }

        if b.width > 0 || b.height > 0 {
            if b.minX < -margin || b.minY < -margin
                || b.maxX > profile.travelX + margin
                || b.maxY > profile.travelY + margin {
                issues.append(.init(
                    severity: .error,
                    message: String(
                        format: "Path bounds %.1f×%.1f mm at (%.1f, %.1f)–(%.1f, %.1f) exceed bed %.0f×%.0f mm.",
                        b.width, b.height, b.minX, b.minY, b.maxX, b.maxY,
                        profile.travelX, profile.travelY
                    )
                ))
            }

            // Work-space bounds can look fine while G54 offset drives machine past travel.
            if let offset {
                let machineBounds = MotionSafety.machineBounds(
                    workBounds: b,
                    offsetX: offset.x,
                    offsetY: offset.y
                )
                if !MotionSafety.fitsTravel(
                    machineBounds,
                    travelX: profile.travelX,
                    travelY: profile.travelY,
                    margin: margin
                ) {
                    issues.append(.init(
                        severity: .error,
                        message: String(
                            format: "With current work offset (G54 ≈ %.1f, %.1f mm), machine path (%.1f, %.1f)–(%.1f, %.1f) exceeds travel %.0f×%.0f mm. Re-home and leave work zero at the homed origin, or move the page.",
                            offset.x, offset.y,
                            machineBounds.minX, machineBounds.minY,
                            machineBounds.maxX, machineBounds.maxY,
                            profile.travelX, profile.travelY
                        )
                    ))
                }
            }
        }

        let softFloor = max(profile.penDownZ - 1.0, 0)
        let softCeil = min(profile.penUpZ + 1.0, profile.travelZ)
        if parse.maxZ > profile.travelZ + 0.1 {
            issues.append(.init(
                severity: .error,
                message: String(format: "Z reaches %.2f mm above travel limit %.0f mm.", parse.maxZ, profile.travelZ)
            ))
        }
        if parse.minZ < softFloor - 0.05 {
            issues.append(.init(
                severity: .error,
                message: String(
                    format: "Z reaches %.2f mm — below safe floor %.2f mm (pen/pressure).",
                    parse.minZ, softFloor
                )
            ))
        }
        if parse.maxZ > softCeil + 0.5 {
            issues.append(.init(
                severity: .warning,
                message: String(format: "Z up to %.2f mm is unusually high vs pen-up %.2f mm.", parse.maxZ, profile.penUpZ)
            ))
        }

        if parse.penChangeCount > 0 {
            issues.append(.init(
                severity: .info,
                message: "\(parse.penChangeCount) pen-change pause(s) (M0) — host will wait for Resume."
            ))
        }

        for item in parse.blocking.prefix(12) {
            issues.append(.init(
                severity: .error,
                message: "Blocked command (unsafe or unsupported for plotting): \(item)"
            ))
        }
        for item in parse.unsupported.prefix(12) {
            issues.append(.init(severity: .warning, message: "Unsupported or risky command: \(item)"))
        }

        let hasError = issues.contains { $0.severity == .error }
        return JobPreflightReport(okToStart: !hasError && !gcode.isEmpty, issues: issues, parse: parse)
    }

    /// Bounding box path as raised pen frame moves (for Frame Job).
    public static func frameGCode(bounds: PlotBounds, profile: MachineProfile, margin: Double = 0) -> String {
        let minX = max(bounds.minX - margin, 0)
        let minY = max(bounds.minY - margin, 0)
        let maxX = min(bounds.maxX + margin, profile.travelX)
        let maxY = min(bounds.maxY + margin, profile.travelY)
        return """
        ; Quill frame job (pen up)
        G21
        G90
        G0 Z\(fmt(profile.penUpZ))
        G0 X\(fmt(minX)) Y\(fmt(minY))
        G0 X\(fmt(maxX)) Y\(fmt(minY))
        G0 X\(fmt(maxX)) Y\(fmt(maxY))
        G0 X\(fmt(minX)) Y\(fmt(maxY))
        G0 X\(fmt(minX)) Y\(fmt(minY))
        """
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
