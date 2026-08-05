import Foundation

/// Pen lift hardware on Bachin-style plotters.
public enum PenHeadType: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Four-wire stepper Z (Bachin T-A4 motor pen).
    case motor
    /// Three-wire hobby servo pen.
    case servo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .motor: return "Motor (4-wire stepper)"
        case .servo: return "Servo (3-wire hobby)"
        }
    }

    public var detail: String {
        switch self {
        case .motor:
            return "T-A4 pen writing machine with motor lift. Quill uses GRBL Z (higher = raised)."
        case .servo:
            return "Hobby servo pen head. Store separate up/down angles; keep clearance safe before writing."
        }
    }
}
