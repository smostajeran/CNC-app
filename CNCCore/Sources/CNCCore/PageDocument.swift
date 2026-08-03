import Foundation

/// Physical page formats placed on the TA-4 bed (machine mm, Y up).
public struct PageFormat: Equatable, Sendable, Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var widthMm: Double
    public var heightMm: Double

    public init(id: String, name: String, widthMm: Double, heightMm: Double) {
        self.id = id
        self.name = name
        self.widthMm = widthMm
        self.heightMm = heightMm
    }

    public static let a4Portrait = PageFormat(id: "a4-portrait", name: "A4 portrait", widthMm: 210, heightMm: 297)
    public static let a4Landscape = PageFormat(id: "a4-landscape", name: "A4 landscape", widthMm: 297, heightMm: 210)
    public static let a5Portrait = PageFormat(id: "a5-portrait", name: "A5 portrait", widthMm: 148, heightMm: 210)
    public static let a5Landscape = PageFormat(id: "a5-landscape", name: "A5 landscape", widthMm: 210, heightMm: 148)
    public static let envelopeDL = PageFormat(id: "envelope-dl", name: "Envelope DL", widthMm: 220, heightMm: 110)
    public static let invitation = PageFormat(id: "invitation", name: "Invitation card", widthMm: 150, heightMm: 150)
    public static let placeCard = PageFormat(id: "place-card", name: "Place card", widthMm: 100, heightMm: 50)
    public static let fullBed = PageFormat(id: "full-bed", name: "Full bed", widthMm: 390, heightMm: 200)

    public static let presets: [PageFormat] = [
        .a4Landscape, .a4Portrait, .a5Landscape, .a5Portrait,
        .envelopeDL, .invitation, .placeCard, .fullBed,
    ]

    public static func custom(widthMm: Double, heightMm: Double) -> PageFormat {
        PageFormat(
            id: "custom-\(Int(widthMm))x\(Int(heightMm))",
            name: "Custom \(Int(widthMm))×\(Int(heightMm)) mm",
            widthMm: widthMm,
            heightMm: heightMm
        )
    }

    /// True if the page can sit entirely on the machine bed.
    public func fits(on profile: MachineProfile) -> Bool {
        widthMm <= profile.travelX + 0.05 && heightMm <= profile.travelY + 0.05
    }
}

/// Pen / paper drawing preset applied to a layer.
public struct PenPreset: Equatable, Sendable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var pressure: Double
    public var drawFeed: Double
    public var liftDelayMs: Double
    public var passes: Int
    public var penDownZ: Double?
    public var penUpZ: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#000000",
        pressure: Double = 0.55,
        drawFeed: Double = 1_500,
        liftDelayMs: Double = 0,
        passes: Int = 1,
        penDownZ: Double? = nil,
        penUpZ: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.pressure = min(max(pressure, 0), 1)
        self.drawFeed = drawFeed
        self.liftDelayMs = max(0, liftDelayMs)
        self.passes = max(1, passes)
        self.penDownZ = penDownZ
        self.penUpZ = penUpZ
    }

    public static let fineliner = PenPreset(name: "Fineliner", colorHex: "#111111", pressure: 0.45, drawFeed: 1_800)
    public static let fountain = PenPreset(name: "Fountain pen", colorHex: "#1B3A6B", pressure: 0.7, drawFeed: 1_000, liftDelayMs: 40)
    public static let marker = PenPreset(name: "Marker", colorHex: "#C0392B", pressure: 0.85, drawFeed: 1_200, passes: 1)

    public static let library: [PenPreset] = [.fineliner, .fountain, .marker]
}

/// One composable item on the page (true physical size in page-local mm).
public struct PageElement: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: Equatable, Sendable, Codable {
        case svg(String)
        case text(String, heightMm: Double)
        case ink(InkDocument)
        case gcode(String)
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Position of element origin on the page (mm, bottom-left of page).
    public var xMm: Double
    public var yMm: Double
    public var rotationDegrees: Double
    public var scale: Double
    public var layerID: UUID
    public var visible: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        xMm: Double = 10,
        yMm: Double = 10,
        rotationDegrees: Double = 0,
        scale: Double = 1,
        layerID: UUID,
        visible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.xMm = xMm
        self.yMm = yMm
        self.rotationDegrees = rotationDegrees
        self.scale = max(0.01, scale)
        self.layerID = layerID
        self.visible = visible
    }
}

public struct PageLayer: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var pen: PenPreset
    public var visible: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        pen: PenPreset = .fineliner,
        visible: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.pen = pen
        self.visible = visible
        self.order = order
    }
}

/// Page placed on the machine bed: paper format + origin + layers + elements.
public struct PageDocument: Equatable, Sendable, Codable {
    public var format: PageFormat
    /// Bottom-left of the page on the machine bed (work coordinates, mm).
    public var bedOriginX: Double
    public var bedOriginY: Double
    public var layers: [PageLayer]
    public var elements: [PageElement]
    public var name: String

    public init(
        format: PageFormat = .a5Landscape,
        bedOriginX: Double = 20,
        bedOriginY: Double = 20,
        layers: [PageLayer] = [],
        elements: [PageElement] = [],
        name: String = "Untitled page"
    ) {
        self.format = format
        self.bedOriginX = bedOriginX
        self.bedOriginY = bedOriginY
        self.layers = layers.isEmpty ? [PageLayer(name: "Pen 1", pen: .fineliner, order: 0)] : layers
        self.elements = elements
        self.name = name
    }

    public var defaultLayerID: UUID { layers.sorted { $0.order < $1.order }.first!.id }

    public var pageBoundsOnBed: PlotBounds {
        PlotBounds(
            minX: bedOriginX,
            minY: bedOriginY,
            maxX: bedOriginX + format.widthMm,
            maxY: bedOriginY + format.heightMm
        )
    }

    public mutating func addLayer(named name: String, pen: PenPreset = .fineliner) -> UUID {
        let order = (layers.map(\.order).max() ?? -1) + 1
        let layer = PageLayer(name: name, pen: pen, order: order)
        layers.append(layer)
        return layer.id
    }

    public mutating func duplicateElement(_ id: UUID, offsetMm: Double = 5) {
        guard let el = elements.first(where: { $0.id == id }) else { return }
        var copy = el
        copy.id = UUID()
        copy.name = el.name + " copy"
        copy.xMm += offsetMm
        copy.yMm += offsetMm
        elements.append(copy)
    }

    public func layer(for id: UUID) -> PageLayer? {
        layers.first { $0.id == id }
    }
}
