import Foundation

public struct HandwritingConfig: Equatable, Sendable {
    public var pen: PenProfile
    public var variation: HumanVariationConfig
    public var seed: UInt64
    public var applyGeometryVariation: Bool
    /// When true, also write feed into PlotPoint for legacy emitters.
    public var annotatePlotJob: Bool

    public init(
        instrument: WritingInstrument = .ballpoint,
        variation: HumanVariationConfig = .neat,
        seed: UInt64 = 42,
        applyGeometryVariation: Bool = true,
        annotatePlotJob: Bool = true
    ) {
        self.pen = .profile(for: instrument)
        self.variation = HumanVariationConfig(
            enabled: variation.enabled,
            positionAmplitudeMm: variation.positionAmplitudeMm,
            baselineDriftMmPerMm: variation.baselineDriftMmPerMm,
            scaleJitter: variation.scaleJitter,
            slantJitterRad: variation.slantJitterRad,
            seed: seed
        )
        self.seed = seed
        self.applyGeometryVariation = applyGeometryVariation
        self.annotatePlotJob = annotatePlotJob
    }

    public init(
        pen: PenProfile,
        variation: HumanVariationConfig = .neat,
        seed: UInt64 = 42,
        applyGeometryVariation: Bool = true,
        annotatePlotJob: Bool = true
    ) {
        self.pen = pen
        self.variation = HumanVariationConfig(
            enabled: variation.enabled,
            positionAmplitudeMm: variation.positionAmplitudeMm,
            baselineDriftMmPerMm: variation.baselineDriftMmPerMm,
            scaleJitter: variation.scaleJitter,
            slantJitterRad: variation.slantJitterRad,
            seed: seed
        )
        self.seed = seed
        self.applyGeometryVariation = applyGeometryVariation
        self.annotatePlotJob = annotatePlotJob
    }

    public static let ballpointNeat = HandwritingConfig(instrument: .ballpoint, variation: .neat, seed: 42)
    public static let fountainNeat = HandwritingConfig(instrument: .fountain, variation: .neat, seed: 42)
}

/// Offline handwriting motion pipeline for Quill plot jobs.
public enum HandwritingSimulator {
    public static func simulate(
        job: PlotJob,
        config: HandwritingConfig = .ballpointNeat
    ) -> [MotionPoint] {
        let geometry = config.applyGeometryVariation
            ? HumanVariationGenerator.vary(job, config: config.variation)
            : job
        let strokes = StrokeAnalyzer.analyze(geometry)
        return MotionPointGenerator.generate(strokes: strokes, pen: config.pen, seed: config.seed)
    }

    /// Annotate a PlotJob with planned pressure (and optional feed) for existing G-code emitters.
    /// Preserves command structure and XY (unless geometry variation is enabled).
    public static func enrich(
        job: PlotJob,
        config: HandwritingConfig = .ballpointNeat
    ) -> PlotJob {
        let geometry = config.applyGeometryVariation
            ? HumanVariationGenerator.vary(job, config: config.variation)
            : job
        let strokes = StrokeAnalyzer.analyze(geometry)

        // Precompute filtered pressure + feed per stroke vertex (including move start).
        var strokePlans: [[(pressure: Double, feed: Double)]] = []
        strokePlans.reserveCapacity(strokes.count)
        for (si, stroke) in strokes.enumerated() {
            let velocities = VelocityPlanner.plan(stroke: stroke, pen: config.pen, letterIndex: si)
            let rawP = PressurePlanner.plan(
                stroke: stroke,
                pen: config.pen,
                velocities: velocities,
                seed: config.seed &+ UInt64(si) &* 17
            )
            let filtered = ServoPressureFilter.filter(
                pressures: rawP,
                arcLengths: stroke.vertices.map(\.s),
                pen: config.pen
            )
            var plan: [(Double, Double)] = []
            for i in stroke.vertices.indices {
                let feed = i < velocities.count ? velocities[i].feedMmMin : config.pen.nominalFeedMmMin
                let pressure = i < filtered.count ? filtered[i] : config.pen.basePressure
                plan.append((pressure, feed))
            }
            strokePlans.append(plan)
        }

        var out: [PlotCommand] = []
        out.reserveCapacity(geometry.commands.count)
        var strokeIndex = -1
        var vertexIndex = 0
        var pendingMove: PlotPoint?

        for cmd in geometry.commands {
            switch cmd {
            case .move(let p):
                pendingMove = p
                // Defer emitting move until first line so we can attach the stroke plan.
            case .line(let p):
                if let m = pendingMove {
                    strokeIndex += 1
                    vertexIndex = 0
                    // Move uses vertex 0; first line uses vertex 1+.
                    if strokeIndex < strokePlans.count, strokePlans[strokeIndex].indices.contains(0) {
                        let xy = config.applyGeometryVariation
                            ? (strokes[strokeIndex].vertices[0].point)
                            : m
                        out.append(.move(PlotPoint(x: xy.x, y: xy.y)))
                    } else {
                        out.append(.move(m))
                    }
                    pendingMove = nil
                    vertexIndex = 1
                } else if strokeIndex < 0 {
                    strokeIndex = 0
                    vertexIndex = 0
                }
                if strokeIndex >= 0,
                   strokeIndex < strokePlans.count,
                   vertexIndex < strokePlans[strokeIndex].count {
                    let plan = strokePlans[strokeIndex][vertexIndex]
                    let xy: PlotPoint
                    if config.applyGeometryVariation,
                       strokeIndex < strokes.count,
                       vertexIndex < strokes[strokeIndex].vertices.count {
                        xy = strokes[strokeIndex].vertices[vertexIndex].point
                    } else {
                        xy = p
                    }
                    out.append(.line(PlotPoint(
                        x: xy.x,
                        y: xy.y,
                        pressure: plan.pressure,
                        feedMmMin: config.annotatePlotJob ? plan.feed : nil
                    )))
                    vertexIndex += 1
                } else {
                    out.append(.line(p.with(pressure: config.pen.basePressure)))
                }
            case .penChange(let label):
                if let m = pendingMove {
                    out.append(.move(m))
                    pendingMove = nil
                }
                out.append(.penChange(label))
            }
        }
        if let m = pendingMove {
            out.append(.move(m))
        }
        return PlotJob(commands: out)
    }

    public static func gcode(
        job: PlotJob,
        profile: MachineProfile,
        config: HandwritingConfig = .ballpointNeat
    ) -> String {
        let points = simulate(job: job, config: config)
        return GCodeExporter.export(points: points, profile: profile, pen: config.pen)
    }
}
