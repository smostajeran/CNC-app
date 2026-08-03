import Foundation

/// Default and live settings for a Bachin T-A4 style pen plotter.
public struct MachineProfile: Equatable, Sendable, Codable {
    public var name: String
    public var baudRate: Int
    public var travelX: Double
    public var travelY: Double
    public var travelZ: Double
    public var penUpZ: Double
    public var penDownZ: Double
    /// Z at lightest pressure (higher = less contact on TA-4 motor lift).
    public var pressureMinZ: Double
    /// Z at hardest pressure (lower = more dig-in; clamped for safety).
    public var pressureMaxZ: Double
    public var jogFeed: Double
    public var drawFeed: Double
    public var invertX: Bool
    public var invertY: Bool
    public var invertZ: Bool
    public var stepsPerMmX: Double?
    public var stepsPerMmY: Double?
    public var stepsPerMmZ: Double?
    public var buildInfo: String?

    /// Minimum pressure delta before emitting a new Z word in G-code (limits Z chatter).
    public static let pressureEpsilon: Double = 0.08

    public init(
        name: String = "TA-4",
        baudRate: Int = 115_200,
        travelX: Double = 390,
        travelY: Double = 200,
        travelZ: Double = 50,
        penUpZ: Double = 5,
        penDownZ: Double = 0,
        pressureMinZ: Double? = nil,
        pressureMaxZ: Double? = nil,
        jogFeed: Double = 2_000,
        drawFeed: Double = 1_500,
        invertX: Bool = false,
        invertY: Bool = false,
        invertZ: Bool = false,
        stepsPerMmX: Double? = nil,
        stepsPerMmY: Double? = nil,
        stepsPerMmZ: Double? = nil,
        buildInfo: String? = nil
    ) {
        self.name = name
        self.baudRate = baudRate
        self.travelX = travelX
        self.travelY = travelY
        self.travelZ = travelZ
        self.penUpZ = penUpZ
        self.penDownZ = penDownZ
        // Light = slightly above default pen-down; hard = slightly below (clamped).
        self.pressureMinZ = pressureMinZ ?? (penDownZ + 1.5)
        self.pressureMaxZ = pressureMaxZ ?? (penDownZ - 0.5)
        self.jogFeed = jogFeed
        self.drawFeed = drawFeed
        self.invertX = invertX
        self.invertY = invertY
        self.invertZ = invertZ
        self.stepsPerMmX = stepsPerMmX
        self.stepsPerMmY = stepsPerMmY
        self.stepsPerMmZ = stepsPerMmZ
        self.buildInfo = buildInfo
        clampPressureRange()
    }

    public static let ta4 = MachineProfile()

    private static let defaultsKey = "quill.machineProfile"
    private static let legacyDefaultsKey = "ta4host.machineProfile"

    /// Soft floor: hard pressure cannot dig more than 1 mm below `penDownZ`, nor below 0 relative to travel.
    public mutating func clampPressureRange() {
        let softFloor = max(penDownZ - 1.0, 0)
        let softCeiling = min(penDownZ + 3.0, travelZ)
        pressureMaxZ = min(max(pressureMaxZ, softFloor), softCeiling)
        pressureMinZ = min(max(pressureMinZ, softFloor), softCeiling)
        // Ensure light Z is numerically above hard Z (less contact).
        if pressureMinZ < pressureMaxZ {
            swap(&pressureMinZ, &pressureMaxZ)
        }
    }

    /// Map normalized pressure `0...1` to motor Z (0 = light, 1 = hard).
    public func z(forPressure p: Double) -> Double {
        let t = min(max(p, 0), 1)
        // Light pressure → pressureMinZ (higher); hard → pressureMaxZ (lower).
        return pressureMinZ + (pressureMaxZ - pressureMinZ) * t
    }

    /// Merge GRBL `$$` settings into this profile when present.
    public mutating func applyGRBLSettings(_ settings: [String: Double]) {
        if let v = settings["$130"] { travelX = v }
        if let v = settings["$131"] { travelY = v }
        if let v = settings["$132"] { travelZ = v }
        if let v = settings["$100"] { stepsPerMmX = v }
        if let v = settings["$101"] { stepsPerMmY = v }
        if let v = settings["$102"] { stepsPerMmZ = v }
        if let dir = settings["$3"] {
            let mask = Int(dir)
            invertX = (mask & 1) != 0
            invertY = (mask & 2) != 0
            invertZ = (mask & 4) != 0
        }
        clampPressureRange()
    }

    /// Correct steps/mm after a distance check: `new = current × (commanded / measured)`.
    /// When measured &lt; commanded the machine moved too little → increase steps/mm.
    public static func correctedStepsPerMm(
        current: Double,
        commandedMm: Double,
        measuredMm: Double
    ) -> Double? {
        guard current > 0, commandedMm > 0, measuredMm > 0.1 else { return nil }
        return current * (commandedMm / measuredMm)
    }

    /// Fallback steps/mm when Probe has not filled `$100`/`$101` yet (typical TA-4).
    public static let defaultStepsPerMm: Double = 80

    /// GRBL `$3` direction invert mask (bit0=X, bit1=Y, bit2=Z).
    public var directionInvertMask: Int {
        var mask = 0
        if invertX { mask |= 1 }
        if invertY { mask |= 2 }
        if invertZ { mask |= 4 }
        return mask
    }

    public func saveToDefaults(_ defaults: UserDefaults = .standard) {
        var copy = self
        copy.clampPressureRange()
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    public static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> MachineProfile? {
        let data = defaults.data(forKey: defaultsKey) ?? defaults.data(forKey: legacyDefaultsKey)
        guard let data else { return nil }
        var profile = try? JSONDecoder().decode(MachineProfile.self, from: data)
        profile?.clampPressureRange()
        return profile
    }

    enum CodingKeys: String, CodingKey {
        case name, baudRate, travelX, travelY, travelZ
        case penUpZ, penDownZ, pressureMinZ, pressureMaxZ
        case jogFeed, drawFeed, invertX, invertY, invertZ
        case stepsPerMmX, stepsPerMmY, stepsPerMmZ, buildInfo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "TA-4"
        baudRate = try c.decodeIfPresent(Int.self, forKey: .baudRate) ?? 115_200
        travelX = try c.decodeIfPresent(Double.self, forKey: .travelX) ?? 390
        travelY = try c.decodeIfPresent(Double.self, forKey: .travelY) ?? 200
        travelZ = try c.decodeIfPresent(Double.self, forKey: .travelZ) ?? 50
        penUpZ = try c.decodeIfPresent(Double.self, forKey: .penUpZ) ?? 5
        penDownZ = try c.decodeIfPresent(Double.self, forKey: .penDownZ) ?? 0
        pressureMinZ = try c.decodeIfPresent(Double.self, forKey: .pressureMinZ) ?? (penDownZ + 1.5)
        pressureMaxZ = try c.decodeIfPresent(Double.self, forKey: .pressureMaxZ) ?? (penDownZ - 0.5)
        jogFeed = try c.decodeIfPresent(Double.self, forKey: .jogFeed) ?? 2_000
        drawFeed = try c.decodeIfPresent(Double.self, forKey: .drawFeed) ?? 1_500
        invertX = try c.decodeIfPresent(Bool.self, forKey: .invertX) ?? false
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? false
        invertZ = try c.decodeIfPresent(Bool.self, forKey: .invertZ) ?? false
        stepsPerMmX = try c.decodeIfPresent(Double.self, forKey: .stepsPerMmX)
        stepsPerMmY = try c.decodeIfPresent(Double.self, forKey: .stepsPerMmY)
        stepsPerMmZ = try c.decodeIfPresent(Double.self, forKey: .stepsPerMmZ)
        buildInfo = try c.decodeIfPresent(String.self, forKey: .buildInfo)
        clampPressureRange()
    }
}
