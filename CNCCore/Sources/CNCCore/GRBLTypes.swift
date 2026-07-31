import Foundation

public enum GRBLConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case fault(String)
}

public struct GRBLStatus: Equatable, Sendable {
    public var state: String
    public var mpos: SIMD3<Double>
    public var wpos: SIMD3<Double>
    public var raw: String

    public init(
        state: String = "Unknown",
        mpos: SIMD3<Double> = .zero,
        wpos: SIMD3<Double> = .zero,
        raw: String = ""
    ) {
        self.state = state
        self.mpos = mpos
        self.wpos = wpos
        self.raw = raw
    }

    /// Parse a GRBL status report like `<Idle|MPos:0.000,0.000,0.000|FS:0,0>`
    public static func parse(_ line: String) -> GRBLStatus? {
        guard line.hasPrefix("<"), line.hasSuffix(">") else { return nil }
        let inner = String(line.dropFirst().dropLast())
        let parts = inner.split(separator: "|").map(String.init)
        guard let state = parts.first else { return nil }

        var status = GRBLStatus(state: state, raw: line)
        for part in parts.dropFirst() {
            if part.hasPrefix("MPos:") {
                status.mpos = parseVec3(String(part.dropFirst(5))) ?? status.mpos
            } else if part.hasPrefix("WPos:") {
                status.wpos = parseVec3(String(part.dropFirst(5))) ?? status.wpos
            }
        }
        return status
    }

    private static func parseVec3(_ text: String) -> SIMD3<Double>? {
        let comps = text.split(separator: ",").compactMap { Double($0) }
        guard comps.count >= 3 else { return nil }
        return SIMD3(comps[0], comps[1], comps[2])
    }
}

public struct GRBLProbeResult: Equatable, Sendable {
    public var buildInfo: String
    public var settingsText: String
    public var settings: [String: Double]
    public var banner: String

    public init(
        buildInfo: String = "",
        settingsText: String = "",
        settings: [String: Double] = [:],
        banner: String = ""
    ) {
        self.buildInfo = buildInfo
        self.settingsText = settingsText
        self.settings = settings
        self.banner = banner
    }

    public static func parseSettings(_ text: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("$"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let valuePart = trimmed[trimmed.index(after: eq)...]
            let number = valuePart.split(separator: " ").first.flatMap { Double($0) }
            if let number {
                result[key] = number
            }
        }
        return result
    }
}

public enum GRBLRealtime {
    public static let status: UInt8 = 0x3F // '?'
    public static let feedHold: UInt8 = 0x21 // '!'
    public static let cycleStart: UInt8 = 0x7E // '~'
    public static let softReset: UInt8 = 0x18 // Ctrl-X
}
