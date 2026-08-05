import Foundation

public enum GRBLConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case fault(String)
}

/// Active limit / control pins from a GRBL `Pn:` field (present only while triggered).
public struct GRBLLimitPins: Equatable, Sendable {
    public var x: Bool
    public var y: Bool
    public var z: Bool
    public var probe: Bool
    public var door: Bool
    public var hold: Bool
    public var softReset: Bool
    public var cycleStart: Bool

    public init(
        x: Bool = false,
        y: Bool = false,
        z: Bool = false,
        probe: Bool = false,
        door: Bool = false,
        hold: Bool = false,
        softReset: Bool = false,
        cycleStart: Bool = false
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.probe = probe
        self.door = door
        self.hold = hold
        self.softReset = softReset
        self.cycleStart = cycleStart
    }

    public var anyXYLimit: Bool { x || y }

    /// Parse `Pn:XYZ` / `Pn:XY` style tokens (letters are active pins).
    public static func parse(_ token: String) -> GRBLLimitPins {
        let body = token.hasPrefix("Pn:") ? String(token.dropFirst(3)) : token
        var pins = GRBLLimitPins()
        for ch in body.uppercased() {
            switch ch {
            case "X": pins.x = true
            case "Y": pins.y = true
            case "Z": pins.z = true
            case "P": pins.probe = true
            case "D": pins.door = true
            case "H": pins.hold = true
            case "R": pins.softReset = true
            case "S": pins.cycleStart = true
            default: break
            }
        }
        return pins
    }
}

public struct GRBLStatus: Equatable, Sendable {
    public var state: String
    public var mpos: SIMD3<Double>
    public var wpos: SIMD3<Double>
    /// Work coordinate offset from `WCO:` when present (`mpos = wpos + wco`).
    public var wco: SIMD3<Double>
    public var sawMPos: Bool
    public var sawWPos: Bool
    public var sawWCO: Bool
    public var pins: GRBLLimitPins
    public var raw: String

    public init(
        state: String = "Unknown",
        mpos: SIMD3<Double> = .zero,
        wpos: SIMD3<Double> = .zero,
        wco: SIMD3<Double> = .zero,
        sawMPos: Bool = false,
        sawWPos: Bool = false,
        sawWCO: Bool = false,
        pins: GRBLLimitPins = GRBLLimitPins(),
        raw: String = ""
    ) {
        self.state = state
        self.mpos = mpos
        self.wpos = wpos
        self.wco = wco
        self.sawMPos = sawMPos
        self.sawWPos = sawWPos
        self.sawWCO = sawWCO
        self.pins = pins
        self.raw = raw
    }

    /// True when machine and work positions are known (parsed or derived via WCO).
    public var hasReliableWorkOffset: Bool {
        (sawMPos && sawWPos) || (sawMPos && sawWCO) || (sawWPos && sawWCO)
    }

    /// Parse a GRBL status report like `<Idle|MPos:0.000,0.000,0.000|WCO:0.000,0.000,0.000|FS:0,0>`
    public static func parse(_ line: String) -> GRBLStatus? {
        guard line.hasPrefix("<"), line.hasSuffix(">") else { return nil }
        let inner = String(line.dropFirst().dropLast())
        let parts = inner.split(separator: "|").map(String.init)
        guard let state = parts.first else { return nil }

        var status = GRBLStatus(state: state, raw: line)
        for part in parts.dropFirst() {
            if part.hasPrefix("MPos:") {
                if let v = parseVec3(String(part.dropFirst(5))) {
                    status.mpos = v
                    status.sawMPos = true
                }
            } else if part.hasPrefix("WPos:") {
                if let v = parseVec3(String(part.dropFirst(5))) {
                    status.wpos = v
                    status.sawWPos = true
                }
            } else if part.hasPrefix("WCO:") {
                if let v = parseVec3(String(part.dropFirst(4))) {
                    status.wco = v
                    status.sawWCO = true
                }
            } else if part.hasPrefix("Pn:") {
                status.pins = GRBLLimitPins.parse(part)
            }
        }
        // GRBL usually reports MPos|WCO or WPos|WCO — not both positions.
        if status.sawMPos, status.sawWCO, !status.sawWPos {
            status.wpos = status.mpos - status.wco
            status.sawWPos = true
        } else if status.sawWPos, status.sawWCO, !status.sawMPos {
            status.mpos = status.wpos + status.wco
            status.sawMPos = true
        } else if status.sawMPos, status.sawWPos, !status.sawWCO {
            status.wco = status.mpos - status.wpos
            status.sawWCO = true
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
