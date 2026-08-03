import Foundation

public enum PageComposerError: Error, LocalizedError, Equatable {
    case emptyPage
    case pageDoesNotFitBed(String)
    case elementFailed(String)
    case outOfPage(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPage: return "Page has no visible elements to plot."
        case .pageDoesNotFitBed(let d): return d
        case .elementFailed(let d): return d
        case .outOfPage(let d): return d
        }
    }
}

public struct ComposedPage: Equatable, Sendable {
    public var job: PlotJob
    public var gcode: String
    public var metrics: JobMetrics
    public var optimizedMetrics: JobMetrics
    public var frameGCode: String
    public var warnings: [String]
    public var hasBlockingOverflow: Bool

    public init(
        job: PlotJob,
        gcode: String,
        metrics: JobMetrics,
        optimizedMetrics: JobMetrics,
        frameGCode: String,
        warnings: [String] = [],
        hasBlockingOverflow: Bool = false
    ) {
        self.job = job
        self.gcode = gcode
        self.metrics = metrics
        self.optimizedMetrics = optimizedMetrics
        self.frameGCode = frameGCode
        self.warnings = warnings
        self.hasBlockingOverflow = hasBlockingOverflow
    }
}

/// Builds machine-space jobs from a true-size page composition.
public enum PageComposer {
    public static func compose(
        _ page: PageDocument,
        profile: MachineProfile,
        optimize: Bool = true
    ) throws -> ComposedPage {
        guard page.format.fits(on: profile) else {
            throw PageComposerError.pageDoesNotFitBed(String(
                format: "Page %.0f×%.0f mm does not fit the %.0f×%.0f mm bed.",
                page.format.widthMm, page.format.heightMm, profile.travelX, profile.travelY
            ))
        }
        let pageBounds = page.pageBoundsOnBed
        if pageBounds.minX < -0.05 || pageBounds.minY < -0.05
            || pageBounds.maxX > profile.travelX + 0.05
            || pageBounds.maxY > profile.travelY + 0.05 {
            throw PageComposerError.pageDoesNotFitBed(
                "Page origin places paper outside the machine bed."
            )
        }

        let layers = page.layers.filter(\.visible).sorted { $0.order < $1.order }
        var layerJobs: [(PageLayer, PlotJob)] = []
        var warnings: [String] = []
        var blockingOverflow = false

        for layer in layers {
            let elems = page.elements
                .filter { $0.visible && $0.layerID == layer.id }
                .sorted { $0.zOrder < $1.zOrder }
            guard !elems.isEmpty else { continue }
            var commands: [PlotCommand] = []
            if layer.pen.pauseBefore {
                commands.append(.penChange("Pause before \(layer.name)"))
            }
            for el in elems {
                if case .textBox(let text, let style) = el.kind {
                    if !style.fontKind.isImplemented {
                        throw PageComposerError.elementFailed(
                            "“\(el.name)”: outline fonts are not implemented yet."
                        )
                    }
                    if !style.overflowPolicy.isImplemented {
                        throw PageComposerError.elementFailed(
                            "“\(el.name)”: truncate is not implemented — choose another overflow policy."
                        )
                    }
                    let layout = TextLayoutEngine.layout(
                        text: text,
                        boxWidthMm: el.widthMm,
                        boxHeightMm: el.heightMm,
                        style: style
                    )
                    if layout.overflows {
                        blockingOverflow = true
                        warnings.append("“\(el.name)”: \(layout.overflowMessage ?? "overflow")")
                    }
                    if !layout.missingGlyphs.isEmpty {
                        warnings.append("“\(el.name)”: missing glyphs \(layout.missingGlyphs.map(String.init).joined())")
                    }
                }
                let local = try plotJob(for: el, profile: profile)
                let placed = transform(local, element: el, page: page)
                let b = placed.bounds
                let outsidePage = b.minX < pageBounds.minX - 0.5 || b.minY < pageBounds.minY - 0.5
                    || b.maxX > pageBounds.maxX + 0.5 || b.maxY > pageBounds.maxY + 0.5
                if outsidePage {
                    // Text overflow already blocks plotting; surface OOB as a blocking warning
                    // instead of throwing so the inspector can show the overflow reason.
                    if case .textBox = el.kind, blockingOverflow {
                        warnings.append("“\(el.name)” extends outside the \(page.format.name) page (overflow).")
                    } else {
                        throw PageComposerError.outOfPage(
                            "“\(el.name)” extends outside the \(page.format.name) page. Move or scale it."
                        )
                    }
                }
                let withPressure = placed.applyingPressure(layer.pen.pressure)
                commands.append(contentsOf: withPressure.commands)
            }
            if layer.pen.pauseAfter {
                commands.append(.penChange("Pause after \(layer.name)"))
            }
            var job = PlotJob(commands: commands)
            if optimize {
                job = PathOptimizer.optimize(job)
            }
            if layer.pen.passes > 1 {
                job = repeatPasses(job, count: layer.pen.passes)
            }
            layerJobs.append((layer, job))
        }

        guard !layerJobs.isEmpty else { throw PageComposerError.emptyPage }

        var merged: [PlotCommand] = []
        for (idx, pair) in layerJobs.enumerated() {
            if idx > 0 {
                merged.append(.penChange(pair.0.pen.name))
            }
            merged.append(contentsOf: pair.1.commands)
        }
        let job = PlotJob(commands: merged)
        let baseGCode = renderGCode(from: job, layers: layerJobs.map(\.0), profile: profile)
        let drawFeed = layerJobs.map(\.0.pen.drawFeed).min() ?? profile.drawFeed
        let metrics = PathOptimizer.metrics(for: job, drawFeed: drawFeed, travelFeed: profile.jogFeed)
        let optimizedJob = PathOptimizer.optimize(job)
        let optimizedMetrics = PathOptimizer.metrics(
            for: optimizedJob,
            drawFeed: drawFeed,
            travelFeed: profile.jogFeed
        )
        let frame = JobPreflight.frameGCode(bounds: pageBounds, profile: profile)
        let useOpt = optimize
        return ComposedPage(
            job: useOpt ? optimizedJob : job,
            gcode: useOpt
                ? renderGCode(from: optimizedJob, layers: layerJobs.map(\.0), profile: profile)
                : baseGCode,
            metrics: metrics,
            optimizedMetrics: optimizedMetrics,
            frameGCode: frame,
            warnings: warnings,
            hasBlockingOverflow: blockingOverflow
        )
    }

    public static func plotJob(for element: PageElement, profile: MachineProfile) throws -> PlotJob {
        var localProfile = profile
        localProfile.travelX = 10_000
        localProfile.travelY = 10_000

        switch element.kind {
        case .svg(let svg):
            return try SVGToGCode.plotJob(from: svg, profile: localProfile, placement: .originalSize)
        case .text(let text, let height):
            return SingleLineText.plotJob(text: text, heightMm: height, origin: PlotPoint(x: 0, y: 0))
        case .textBox(let text, let style):
            let layout = TextLayoutEngine.layout(
                text: text,
                boxWidthMm: element.widthMm,
                boxHeightMm: element.heightMm,
                style: style
            )
            return TextLayoutEngine.plotJob(layout: layout, style: style)
        case .ink(let doc):
            return doc.plotJob(smoothed: true)
        case .gcode(let text):
            return GCodeParser.parse(text, defaultFeed: profile.drawFeed, defaultRapid: profile.jogFeed).plotJob
        case .shape(let kind):
            return shapeJob(kind, width: element.widthMm, height: element.heightMm)
        }
    }

    public static func transform(_ job: PlotJob, element: PageElement, page: PageDocument) -> PlotJob {
        let rad = element.rotationDegrees * .pi / 180
        let cosR = cos(rad)
        let sinR = sin(rad)
        let origin = element.frameOriginPaper
        let ox = page.bedOriginX + origin.x
        let oy = page.bedOriginY + origin.y
        let s = element.scale
        // Rotate around anchor point in paper space.
        let anchorPaperX = element.xMm
        let anchorPaperY = element.yMm
        let ax = page.bedOriginX + anchorPaperX
        let ay = page.bedOriginY + anchorPaperY

        let commands = job.commands.map { cmd -> PlotCommand in
            switch cmd {
            case .move(let p):
                return .move(map(p, cosR: cosR, sinR: sinR, scale: s, ox: ox, oy: oy, ax: ax, ay: ay))
            case .line(let p):
                return .line(map(p, cosR: cosR, sinR: sinR, scale: s, ox: ox, oy: oy, ax: ax, ay: ay))
            case .penChange(let label):
                return .penChange(label)
            }
        }
        return PlotJob(commands: commands)
    }

    private static func shapeJob(_ kind: PageElement.ShapeKind, width: Double, height: Double) -> PlotJob {
        switch kind {
        case .rect, .roundedRect:
            return PlotJob(commands: [
                .move(PlotPoint(x: 0, y: 0)),
                .line(PlotPoint(x: width, y: 0)),
                .line(PlotPoint(x: width, y: height)),
                .line(PlotPoint(x: 0, y: height)),
                .line(PlotPoint(x: 0, y: 0)),
            ])
        case .line:
            return PlotJob(commands: [
                .move(PlotPoint(x: 0, y: height / 2)),
                .line(PlotPoint(x: width, y: height / 2)),
            ])
        case .circle, .ellipse:
            let cx = width / 2, cy = height / 2
            let rx = width / 2, ry = height / 2
            var cmds: [PlotCommand] = []
            let steps = 48
            for i in 0...steps {
                let t = Double(i) / Double(steps) * 2 * .pi
                let p = PlotPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
                cmds.append(i == 0 ? .move(p) : .line(p))
            }
            return PlotJob(commands: cmds)
        case .polygon:
            let n = 6
            let cx = width / 2, cy = height / 2
            let rx = width / 2, ry = height / 2
            var cmds: [PlotCommand] = []
            for i in 0...n {
                let t = Double(i) / Double(n) * 2 * .pi - .pi / 2
                let p = PlotPoint(x: cx + rx * cos(t), y: cy + ry * sin(t))
                cmds.append(i == 0 ? .move(p) : .line(p))
            }
            return PlotJob(commands: cmds)
        case .freehand:
            return PlotJob(commands: [
                .move(PlotPoint(x: 0, y: 0)),
                .line(PlotPoint(x: width * 0.3, y: height * 0.6)),
                .line(PlotPoint(x: width * 0.7, y: height * 0.4)),
                .line(PlotPoint(x: width, y: height)),
            ])
        }
    }

    private static func map(
        _ p: PlotPoint,
        cosR: Double,
        sinR: Double,
        scale: Double,
        ox: Double,
        oy: Double,
        ax: Double,
        ay: Double
    ) -> PlotPoint {
        // Local (unrotated) point in bed space from frame origin, then rotate about anchor.
        let lx = ox + p.x * scale
        let ly = oy + p.y * scale
        let dx = lx - ax
        let dy = ly - ay
        let rx = dx * cosR - dy * sinR
        let ry = dx * sinR + dy * cosR
        return PlotPoint(x: ax + rx, y: ay + ry, pressure: p.pressure)
    }

    private static func repeatPasses(_ job: PlotJob, count: Int) -> PlotJob {
        var commands: [PlotCommand] = []
        for _ in 0..<count {
            commands.append(contentsOf: job.commands)
        }
        return PlotJob(commands: commands)
    }

    private static func renderGCode(from job: PlotJob, layers: [PageLayer], profile: MachineProfile) -> String {
        var lines: [String] = [
            "; Quill page composition",
            "G21",
            "G90",
            "G0 Z\(fmt(profile.penUpZ))",
        ]
        var penDown = false
        var lastPressure: Double?
        var layerIdx = 0
        var activePen = layers.first?.pen

        for cmd in job.commands {
            switch cmd {
            case .penChange(let label):
                if penDown {
                    lines.append("G0 Z\(fmt(profile.penUpZ))")
                    penDown = false
                    lastPressure = nil
                }
                lines.append("; PEN CHANGE: \(label)")
                lines.append("M0")
                layerIdx = min(layerIdx + 1, max(layers.count - 1, 0))
                if layerIdx < layers.count {
                    activePen = layers[layerIdx].pen
                }
            case .move(let p):
                if penDown {
                    lines.append("G0 Z\(fmt(profile.penUpZ))")
                    penDown = false
                    lastPressure = nil
                }
                lines.append("G0 X\(fmt(p.x)) Y\(fmt(p.y))")
            case .line(let p):
                let pressure = p.pressure ?? activePen?.pressure ?? 0.5
                let feed = activePen?.drawFeed ?? profile.drawFeed
                var zProfile = profile
                if let down = activePen?.penDownZ { zProfile.penDownZ = down }
                if let up = activePen?.penUpZ { zProfile.penUpZ = up }
                zProfile.clampPressureRange()
                if !penDown {
                    let z = zProfile.z(forPressure: pressure)
                    lines.append("G1 Z\(fmt(z)) F\(fmt(feed))")
                    if let delay = activePen?.liftDelayMs, delay > 0 {
                        lines.append(String(format: "G4 P%.3f", delay / 1000))
                    }
                    penDown = true
                    lastPressure = pressure
                    lines.append("G1 X\(fmt(p.x)) Y\(fmt(p.y)) F\(fmt(feed))")
                } else if abs(pressure - (lastPressure ?? pressure)) >= MachineProfile.pressureEpsilon {
                    let z = zProfile.z(forPressure: pressure)
                    lines.append("G1 X\(fmt(p.x)) Y\(fmt(p.y)) Z\(fmt(z)) F\(fmt(feed))")
                    lastPressure = pressure
                } else {
                    lines.append("G1 X\(fmt(p.x)) Y\(fmt(p.y)) F\(fmt(feed))")
                }
            }
        }
        if penDown {
            lines.append("G0 Z\(fmt(profile.penUpZ))")
        }
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
