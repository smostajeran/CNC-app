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

    public init(job: PlotJob, gcode: String, metrics: JobMetrics, optimizedMetrics: JobMetrics, frameGCode: String) {
        self.job = job
        self.gcode = gcode
        self.metrics = metrics
        self.optimizedMetrics = optimizedMetrics
        self.frameGCode = frameGCode
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

        for layer in layers {
            let elems = page.elements.filter { $0.visible && $0.layerID == layer.id }
            guard !elems.isEmpty else { continue }
            var commands: [PlotCommand] = []
            for el in elems {
                let local = try plotJob(for: el, profile: profile)
                let placed = transform(local, element: el, page: page)
                // Soft check: warn via error if content leaves the page rectangle significantly.
                let b = placed.bounds
                if b.minX < pageBounds.minX - 0.5 || b.minY < pageBounds.minY - 0.5
                    || b.maxX > pageBounds.maxX + 0.5 || b.maxY > pageBounds.maxY + 0.5 {
                    throw PageComposerError.outOfPage(
                        "“\(el.name)” extends outside the \(page.format.name) page. Move or scale it."
                    )
                }
                let withPressure = placed.applyingPressure(layer.pen.pressure)
                commands.append(contentsOf: withPressure.commands)
            }
            var job = PlotJob(commands: commands)
            if optimize {
                job = PathOptimizer.optimize(job)
            }
            // Multi-pass: repeat draw paths.
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
        return ComposedPage(
            job: optimize ? optimizedJob : job,
            gcode: optimize
                ? renderGCode(from: optimizedJob, layers: layerJobs.map(\.0), profile: profile)
                : baseGCode,
            metrics: metrics,
            optimizedMetrics: optimizedMetrics,
            frameGCode: frame
        )
    }

    public static func plotJob(for element: PageElement, profile: MachineProfile) throws -> PlotJob {
        // Extract in local coordinates without machine-bed rejection; page bounds are checked after transform.
        var localProfile = profile
        localProfile.travelX = 10_000
        localProfile.travelY = 10_000

        switch element.kind {
        case .svg(let svg):
            return try SVGToGCode.plotJob(from: svg, profile: localProfile, placement: .originalSize)
        case .text(let text, let height):
            return SingleLineText.plotJob(text: text, heightMm: height, origin: PlotPoint(x: 0, y: 0))
        case .ink(let doc):
            return doc.plotJob(smoothed: true)
        case .gcode(let text):
            return GCodeParser.parse(text, defaultFeed: profile.drawFeed, defaultRapid: profile.jogFeed).plotJob
        }
    }

    public static func transform(_ job: PlotJob, element: PageElement, page: PageDocument) -> PlotJob {
        let rad = element.rotationDegrees * .pi / 180
        let cosR = cos(rad)
        let sinR = sin(rad)
        let ox = page.bedOriginX + element.xMm
        let oy = page.bedOriginY + element.yMm
        let s = element.scale

        let commands = job.commands.map { cmd -> PlotCommand in
            switch cmd {
            case .move(let p):
                return .move(map(p, cosR: cosR, sinR: sinR, scale: s, ox: ox, oy: oy))
            case .line(let p):
                return .line(map(p, cosR: cosR, sinR: sinR, scale: s, ox: ox, oy: oy))
            case .penChange(let label):
                return .penChange(label)
            }
        }
        return PlotJob(commands: commands)
    }

    private static func map(
        _ p: PlotPoint,
        cosR: Double,
        sinR: Double,
        scale: Double,
        ox: Double,
        oy: Double
    ) -> PlotPoint {
        let x = p.x * scale
        let y = p.y * scale
        let rx = x * cosR - y * sinR
        let ry = x * sinR + y * cosR
        return PlotPoint(x: ox + rx, y: oy + ry, pressure: p.pressure)
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
