import Foundation

public struct GCodeNormalizeResult: Equatable, Sendable {
    public var text: String
    public var substitutions: Int

    public init(text: String, substitutions: Int) {
        self.text = text
        self.substitutions = substitutions
    }
}

/// Rewrites common servo/laser pen commands into motor-Z moves for TA-4 style machines.
public enum GCodeNormalizer {
    /// Maps `M3`/`M03`/`SM03` → pen down, `M5`/`M05` → pen up.
    public static func normalizePenCommands(_ text: String, profile: MachineProfile) -> GCodeNormalizeResult {
        var out: [String] = []
        var subs = 0
        let penDown = String(format: "G1 Z%.3f F%.3f", profile.penDownZ, profile.drawFeed)
        let penUp = String(format: "G0 Z%.3f", profile.penUpZ)

        for raw in text.split(whereSeparator: \.isNewline, omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if isPenDown(upper) {
                out.append(penDown)
                subs += 1
            } else if isPenUp(upper) {
                out.append(penUp)
                subs += 1
            } else {
                out.append(line)
            }
        }

        return GCodeNormalizeResult(text: out.joined(separator: "\n"), substitutions: subs)
    }

    private static func isPenDown(_ upper: String) -> Bool {
        let cmd = stripComment(upper)
        if cmd.hasPrefix("SM03") { return true }
        if cmd.hasPrefix("M03") || cmd.hasPrefix("M3") {
            // Avoid matching M30 etc.
            let rest = cmd.dropFirst(cmd.hasPrefix("M03") ? 3 : 2)
            return rest.isEmpty || rest.first?.isWhitespace == true || rest.first == "S"
        }
        return false
    }

    private static func isPenUp(_ upper: String) -> Bool {
        let cmd = stripComment(upper)
        if cmd.hasPrefix("M05") || cmd.hasPrefix("M5") {
            let rest = cmd.dropFirst(cmd.hasPrefix("M05") ? 3 : 2)
            return rest.isEmpty || rest.first?.isWhitespace == true || rest.first == "S"
        }
        return false
    }

    private static func stripComment(_ line: String) -> String {
        if let idx = line.firstIndex(of: ";") {
            return String(line[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}
