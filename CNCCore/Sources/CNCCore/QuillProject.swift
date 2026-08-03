import Foundation

/// Versioned `.quill` project document (JSON).
public struct QuillProject: Equatable, Sendable, Codable {
    public static let currentVersion = 2

    public var version: Int
    public var page: PageDocument
    public var batch: BatchDocument
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        version: Int = QuillProject.currentVersion,
        page: PageDocument = PageDocument(),
        batch: BatchDocument = BatchDocument(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.version = version
        self.page = page
        self.batch = batch
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.page.migrateLegacyText()
    }

    public mutating func touch() {
        modifiedAt = Date()
        version = Self.currentVersion
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func load(from data: Data) throws -> QuillProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(QuillProject.self, from: data)
        project.page.migrateLegacyText()
        if project.version < currentVersion {
            project.version = currentVersion
        }
        return project
    }

    public static func load(from url: URL) throws -> QuillProject {
        try load(from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try jsonData().write(to: url, options: .atomic)
    }
}

/// Undo/redo stack over `QuillProject` snapshots.
public final class DocumentHistory: @unchecked Sendable {
    private var undoStack: [QuillProject] = []
    private var redoStack: [QuillProject] = []
    private let limit: Int

    public init(limit: Int = 80) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func checkpoint(_ project: QuillProject) {
        undoStack.append(project)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    public func undo(current: QuillProject) -> QuillProject? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public func redo(current: QuillProject) -> QuillProject? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

public enum SnapEngine {
    public static func snapPosition(
        x: Double,
        y: Double,
        page: PageDocument,
        elementSize: (w: Double, h: Double),
        disableSnap: Bool
    ) -> (x: Double, y: Double) {
        guard !disableSnap else { return (x, y) }
        var sx = x
        var sy = y
        let settings = page.editor

        if settings.snapToGrid {
            sx = PageDocument.snap(sx, spacing: settings.gridSpacingMm)
            sy = PageDocument.snap(sy, spacing: settings.gridSpacingMm)
        }
        if settings.snapToPaper {
            let edgesX = [0.0, page.format.widthMm / 2, page.format.widthMm]
            let edgesY = [0.0, page.format.heightMm / 2, page.format.heightMm]
            if let nx = nearest(sx, among: edgesX, threshold: settings.gridSpacingMm * 0.4) { sx = nx }
            if let ny = nearest(sy, among: edgesY, threshold: settings.gridSpacingMm * 0.4) { sy = ny }
        }
        if settings.snapToObjects {
            var xs: [Double] = []
            var ys: [Double] = []
            for el in page.elements {
                let o = el.frameOriginPaper
                xs += [o.x, o.x + el.widthMm * el.scale / 2, o.x + el.widthMm * el.scale]
                ys += [o.y, o.y + el.heightMm * el.scale / 2, o.y + el.heightMm * el.scale]
            }
            if let nx = nearest(sx, among: xs, threshold: 1.5) { sx = nx }
            if let ny = nearest(sy, among: ys, threshold: 1.5) { sy = ny }
        }
        for guide in settings.guides {
            switch guide.orientation {
            case .vertical:
                if abs(sx - guide.positionMm) < 1.5 { sx = guide.positionMm }
            case .horizontal:
                if abs(sy - guide.positionMm) < 1.5 { sy = guide.positionMm }
            }
        }
        _ = elementSize
        return (sx, sy)
    }

    private static func nearest(_ value: Double, among candidates: [Double], threshold: Double) -> Double? {
        var best: Double?
        var bestDist = threshold
        for c in candidates {
            let d = abs(c - value)
            if d < bestDist {
                bestDist = d
                best = c
            }
        }
        return best
    }
}
