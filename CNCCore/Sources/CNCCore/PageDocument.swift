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

    public func fits(on profile: MachineProfile) -> Bool {
        widthMm <= profile.travelX + 0.05 && heightMm <= profile.travelY + 0.05
    }
}

public struct PenPreset: Equatable, Sendable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var pressure: Double
    public var drawFeed: Double
    public var liftDelayMs: Double
    public var passes: Int
    public var pauseBefore: Bool
    public var pauseAfter: Bool
    public var penDownZ: Double?
    public var penUpZ: Double?
    /// Instrument model for human pressure / velocity planning.
    public var writingInstrument: WritingInstrument
    /// When true, Compose runs the handwriting pressure/velocity pipeline on this layer’s paths.
    public var handwritingMotion: Bool
    /// When true, also apply small seeded XY imperfections (off by default for layout fidelity).
    public var handwritingGeometryVariation: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#000000",
        pressure: Double = 0.55,
        drawFeed: Double = 1_500,
        liftDelayMs: Double = 0,
        passes: Int = 1,
        pauseBefore: Bool = false,
        pauseAfter: Bool = false,
        penDownZ: Double? = nil,
        penUpZ: Double? = nil,
        writingInstrument: WritingInstrument = .ballpoint,
        handwritingMotion: Bool = true,
        handwritingGeometryVariation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.pressure = min(max(pressure, 0), 1)
        self.drawFeed = drawFeed
        self.liftDelayMs = max(0, liftDelayMs)
        self.passes = max(1, passes)
        self.pauseBefore = pauseBefore
        self.pauseAfter = pauseAfter
        self.penDownZ = penDownZ
        self.penUpZ = penUpZ
        self.writingInstrument = writingInstrument
        self.handwritingMotion = handwritingMotion
        self.handwritingGeometryVariation = handwritingGeometryVariation
    }

    public static let fineliner = PenPreset(
        name: "Fineliner",
        colorHex: "#111111",
        pressure: 0.45,
        drawFeed: 1_800,
        writingInstrument: .gel
    )
    public static let fountain = PenPreset(
        name: "Fountain pen",
        colorHex: "#1B3A6B",
        pressure: 0.22,
        drawFeed: 900,
        liftDelayMs: 40,
        writingInstrument: .fountain
    )
    public static let marker = PenPreset(
        name: "Marker",
        colorHex: "#C0392B",
        pressure: 0.20,
        drawFeed: 1_100,
        passes: 1,
        writingInstrument: .marker
    )
    public static let ballpoint = PenPreset(
        name: "Ballpoint",
        colorHex: "#111111",
        pressure: 0.55,
        drawFeed: 1_500,
        writingInstrument: .ballpoint
    )
    public static let library: [PenPreset] = [.ballpoint, .fineliner, .fountain, .marker]

    enum CodingKeys: String, CodingKey {
        case id, name, colorHex, pressure, drawFeed, liftDelayMs, passes
        case pauseBefore, pauseAfter, penDownZ, penUpZ
        case writingInstrument, handwritingMotion, handwritingGeometryVariation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#000000"
        pressure = min(max(try c.decodeIfPresent(Double.self, forKey: .pressure) ?? 0.55, 0), 1)
        drawFeed = try c.decodeIfPresent(Double.self, forKey: .drawFeed) ?? 1_500
        liftDelayMs = try c.decodeIfPresent(Double.self, forKey: .liftDelayMs) ?? 0
        passes = max(1, try c.decodeIfPresent(Int.self, forKey: .passes) ?? 1)
        pauseBefore = try c.decodeIfPresent(Bool.self, forKey: .pauseBefore) ?? false
        pauseAfter = try c.decodeIfPresent(Bool.self, forKey: .pauseAfter) ?? false
        penDownZ = try c.decodeIfPresent(Double.self, forKey: .penDownZ)
        penUpZ = try c.decodeIfPresent(Double.self, forKey: .penUpZ)
        writingInstrument = try c.decodeIfPresent(WritingInstrument.self, forKey: .writingInstrument) ?? .ballpoint
        handwritingMotion = try c.decodeIfPresent(Bool.self, forKey: .handwritingMotion) ?? true
        handwritingGeometryVariation = try c.decodeIfPresent(Bool.self, forKey: .handwritingGeometryVariation) ?? false
    }
}

/// Nine-point element anchor (named to avoid clashing with SwiftUI’s Anchor APIs).
public enum PageAnchor: String, Equatable, Sendable, Codable, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .topLeft: return "Top-left"
        case .topCenter: return "Top-centre"
        case .topRight: return "Top-right"
        case .centerLeft: return "Centre-left"
        case .center: return "Centre"
        case .centerRight: return "Centre-right"
        case .bottomLeft: return "Bottom-left"
        case .bottomCenter: return "Bottom-centre"
        case .bottomRight: return "Bottom-right"
        }
    }

    /// Fraction of width/height from bottom-left origin (x: 0…1, y: 0…1, Y up).
    public var fractions: (x: Double, y: Double) {
        switch self {
        case .bottomLeft: return (0, 0)
        case .bottomCenter: return (0.5, 0)
        case .bottomRight: return (1, 0)
        case .centerLeft: return (0, 0.5)
        case .center: return (0.5, 0.5)
        case .centerRight: return (1, 0.5)
        case .topLeft: return (0, 1)
        case .topCenter: return (0.5, 1)
        case .topRight: return (1, 1)
        }
    }
}

public enum CoordinateSpace: String, Equatable, Sendable, Codable, CaseIterable {
    case paper
    case bed
}

public struct GuideLine: Equatable, Sendable, Codable, Identifiable {
    public enum Orientation: String, Codable, Sendable { case horizontal, vertical }
    public var id: UUID
    public var orientation: Orientation
    /// Position in paper mm (from bottom-left for both; vertical = X, horizontal = Y).
    public var positionMm: Double

    public init(id: UUID = UUID(), orientation: Orientation, positionMm: Double) {
        self.id = id
        self.orientation = orientation
        self.positionMm = positionMm
    }
}

public struct EditorSettings: Equatable, Sendable, Codable {
    public var gridSpacingMm: Double
    public var showGrid: Bool
    public var snapToGrid: Bool
    public var snapToPaper: Bool
    public var snapToObjects: Bool
    public var marginMm: Double
    public var coordinateSpace: CoordinateSpace
    public var guides: [GuideLine]
    public var nudgeFineMm: Double
    public var nudgeNormalMm: Double
    public var nudgeLargeMm: Double

    public init(
        gridSpacingMm: Double = 5,
        showGrid: Bool = true,
        snapToGrid: Bool = true,
        snapToPaper: Bool = true,
        snapToObjects: Bool = true,
        marginMm: Double = 5,
        coordinateSpace: CoordinateSpace = .paper,
        guides: [GuideLine] = [],
        nudgeFineMm: Double = 0.1,
        nudgeNormalMm: Double = 1,
        nudgeLargeMm: Double = 10
    ) {
        self.gridSpacingMm = max(0.5, gridSpacingMm)
        self.showGrid = showGrid
        self.snapToGrid = snapToGrid
        self.snapToPaper = snapToPaper
        self.snapToObjects = snapToObjects
        self.marginMm = max(0, marginMm)
        self.coordinateSpace = coordinateSpace
        self.guides = guides
        self.nudgeFineMm = nudgeFineMm
        self.nudgeNormalMm = nudgeNormalMm
        self.nudgeLargeMm = nudgeLargeMm
    }
}

/// One composable item on the page (geometry in millimetres).
public struct PageElement: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: Equatable, Sendable, Codable {
        case svg(String)
        /// Legacy short text — migrated to `textBox` on load when possible.
        case text(String, heightMm: Double)
        case textBox(text: String, style: TextBoxStyle)
        case ink(InkDocument)
        case gcode(String)
        case shape(ShapeKind)
    }

    public enum ShapeKind: String, Equatable, Sendable, Codable {
        case line, rect, roundedRect, circle, ellipse, polygon, freehand
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Anchor position on the page (paper mm, Y up from page bottom-left).
    public var xMm: Double
    public var yMm: Double
    public var widthMm: Double
    public var heightMm: Double
    public var rotationDegrees: Double
    public var scale: Double
    public var lockAspect: Bool
    public var anchor: PageAnchor
    public var layerID: UUID
    public var zOrder: Int
    public var visible: Bool
    public var locked: Bool
    public var groupID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        xMm: Double = 10,
        yMm: Double = 10,
        widthMm: Double = 80,
        heightMm: Double = 40,
        rotationDegrees: Double = 0,
        scale: Double = 1,
        lockAspect: Bool = false,
        anchor: PageAnchor = .bottomLeft,
        layerID: UUID,
        zOrder: Int = 0,
        visible: Bool = true,
        locked: Bool = false,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.xMm = xMm
        self.yMm = yMm
        self.widthMm = max(1, widthMm)
        self.heightMm = max(1, heightMm)
        self.rotationDegrees = rotationDegrees
        self.scale = max(0.01, scale)
        self.lockAspect = lockAspect
        self.anchor = anchor
        self.layerID = layerID
        self.zOrder = zOrder
        self.visible = visible
        self.locked = locked
        self.groupID = groupID
    }

    public var typeLabel: String {
        switch kind {
        case .svg: return "SVG"
        case .text, .textBox: return "Text"
        case .ink: return "Ink"
        case .gcode: return "G-code"
        case .shape(let s): return s.rawValue.capitalized
        }
    }

    /// Bottom-left of the unrotated axis-aligned box in paper space.
    public var frameOriginPaper: (x: Double, y: Double) {
        let f = anchor.fractions
        let w = widthMm * scale
        let h = heightMm * scale
        return (xMm - f.x * w, yMm - f.y * h)
    }

    public mutating func setAnchorPosition(x: Double, y: Double) {
        xMm = x
        yMm = y
    }
}

public struct PageLayer: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var pen: PenPreset
    public var visible: Bool
    public var locked: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        pen: PenPreset = .fineliner,
        visible: Bool = true,
        locked: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.pen = pen
        self.visible = visible
        self.locked = locked
        self.order = order
    }
}

/// Page placed on the machine bed: paper format + origin + layers + elements.
public struct PageDocument: Equatable, Sendable, Codable {
    public var format: PageFormat
    public var bedOriginX: Double
    public var bedOriginY: Double
    public var pageRotationDegrees: Double
    public var layers: [PageLayer]
    public var elements: [PageElement]
    public var name: String
    public var editor: EditorSettings
    public var optimizePaths: Bool

    public init(
        format: PageFormat = .a5Landscape,
        bedOriginX: Double = 20,
        bedOriginY: Double = 20,
        pageRotationDegrees: Double = 0,
        layers: [PageLayer] = [],
        elements: [PageElement] = [],
        name: String = "Untitled page",
        editor: EditorSettings = EditorSettings(),
        optimizePaths: Bool = true
    ) {
        self.format = format
        self.bedOriginX = bedOriginX
        self.bedOriginY = bedOriginY
        self.pageRotationDegrees = pageRotationDegrees
        self.layers = layers.isEmpty ? [PageLayer(name: "Pen 1", pen: .fineliner, order: 0)] : layers
        self.elements = elements
        self.name = name
        self.editor = editor
        self.optimizePaths = optimizePaths
        migrateLegacyText()
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
        copy.zOrder = (elements.map(\.zOrder).max() ?? 0) + 1
        elements.append(copy)
    }

    public func layer(for id: UUID) -> PageLayer? {
        layers.first { $0.id == id }
    }

    public mutating func migrateLegacyText() {
        for i in elements.indices {
            if case .text(let t, let h) = elements[i].kind {
                var style = TextBoxStyle(fontSizeMm: h)
                style.heightMode = .automatic
                elements[i].kind = .textBox(text: t, style: style)
                if elements[i].heightMm < h * 2 {
                    elements[i].heightMm = max(h * 3, 30)
                }
            }
        }
    }

    /// Persist automatic / expand-box heights onto each text element so canvas,
    /// inspector, save/load, preview, and G-code share identical dimensions.
    @discardableResult
    public mutating func applyTextBoxSizing() -> Bool {
        var changed = false
        for i in elements.indices {
            guard case .textBox(let text, let style) = elements[i].kind else { continue }
            let layout = TextLayoutEngine.layout(
                text: text,
                boxWidthMm: elements[i].widthMm,
                boxHeightMm: elements[i].heightMm,
                style: style
            )
            if style.heightMode == .automatic || style.overflowPolicy == .expandBox {
                let needed = max(layout.contentHeightMm + style.paddingMm * 2, style.fontSizeMm + style.paddingMm * 2)
                if abs(elements[i].heightMm - needed) > 0.05 {
                    elements[i].heightMm = needed
                    changed = true
                }
            }
        }
        return changed
    }

    /// True when any visible text box currently overflows (hard plot blocker).
    public func hasTextOverflow() -> Bool {
        for el in elements where el.visible {
            if case .textBox(let text, let style) = el.kind {
                let layout = TextLayoutEngine.layout(
                    text: text,
                    boxWidthMm: el.widthMm,
                    boxHeightMm: el.heightMm,
                    style: style
                )
                if layout.overflows { return true }
            }
        }
        return false
    }

    /// Convert paper-space point to bed coordinates.
    public func paperToBed(x: Double, y: Double) -> (x: Double, y: Double) {
        (bedOriginX + x, bedOriginY + y)
    }

    public func bedToPaper(x: Double, y: Double) -> (x: Double, y: Double) {
        (x - bedOriginX, y - bedOriginY)
    }

    public static func snap(_ value: Double, spacing: Double) -> Double {
        guard spacing > 0 else { return value }
        return (value / spacing).rounded() * spacing
    }
}
