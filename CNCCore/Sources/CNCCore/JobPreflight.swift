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
        isBusy: Bool = false
    ) -> JobPreflightReport {
        var issues: [PreflightIssue] = []
        let parse = GCodeParser.parse(gcode, defaultFeed: profile.drawFeed, defaultRapid: profile.jogFeed)

        if gcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "No G-code loaded."))
        }

        if isBusy {
            issues.append(.init(severity: .error, message: "Controller is busy with another operation."))
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
                message: "Work zero has not been set in this session — confirm origin before inking."
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
