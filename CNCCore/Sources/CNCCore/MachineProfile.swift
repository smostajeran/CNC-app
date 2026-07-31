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
    public var jogFeed: Double
    public var drawFeed: Double
    public var invertX: Bool
    public var invertY: Bool
    public var invertZ: Bool
    public var stepsPerMmX: Double?
    public var stepsPerMmY: Double?
    public var stepsPerMmZ: Double?
    public var buildInfo: String?

    public init(
        name: String = "TA-4",
        baudRate: Int = 115_200,
        travelX: Double = 390,
        travelY: Double = 200,
        travelZ: Double = 50,
        penUpZ: Double = 5,
        penDownZ: Double = 0,
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
        self.jogFeed = jogFeed
        self.drawFeed = drawFeed
        self.invertX = invertX
        self.invertY = invertY
        self.invertZ = invertZ
        self.stepsPerMmX = stepsPerMmX
        self.stepsPerMmY = stepsPerMmY
        self.stepsPerMmZ = stepsPerMmZ
        self.buildInfo = buildInfo
    }

    public static let ta4 = MachineProfile()

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
    }

    /// GRBL `$3` direction invert mask (bit0=X, bit1=Y, bit2=Z).
    public var directionInvertMask: Int {
        var mask = 0
        if invertX { mask |= 1 }
        if invertY { mask |= 2 }
        if invertZ { mask |= 4 }
        return mask
    }

    /// Correct steps/mm after a distance check: `new = current × (commanded / measured)`.
    public static func correctedStepsPerMm(
        current: Double,
        commandedMm: Double,
        measuredMm: Double
    ) -> Double? {
        guard current > 0, commandedMm > 0, measuredMm > 0.1 else { return nil }
        return current * (commandedMm / measuredMm)
    }
}
