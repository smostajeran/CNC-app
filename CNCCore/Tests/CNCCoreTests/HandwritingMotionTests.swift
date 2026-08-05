import XCTest
@testable import CNCCore

final class HandwritingMotionTests: XCTestCase {
    private func sampleStrokeJob() -> PlotJob {
        // Horizontal then downward hook — exercises direction + release.
        PlotJob(commands: [
            .move(PlotPoint(x: 0, y: 20)),
            .line(PlotPoint(x: 10, y: 20)),
            .line(PlotPoint(x: 20, y: 20)),
            .line(PlotPoint(x: 30, y: 20)),
            .line(PlotPoint(x: 40, y: 18)),
            .line(PlotPoint(x: 48, y: 12)),
            .line(PlotPoint(x: 52, y: 4)),
        ])
    }

    func testSmoothstepBounds() {
        XCTAssertEqual(HandwritingMath.smoothstep(0), 0, accuracy: 1e-9)
        XCTAssertEqual(HandwritingMath.smoothstep(1), 1, accuracy: 1e-9)
        XCTAssertEqual(HandwritingMath.smoothstep(0.5), 0.5, accuracy: 1e-9)
    }

    func testStrokeStartPressureBelowCruise() {
        let job = sampleStrokeJob()
        let config = HandwritingConfig(
            instrument: .ballpoint,
            variation: .off,
            seed: 7,
            applyGeometryVariation: false
        )
        let points = HandwritingSimulator.simulate(job: job, config: config)
        XCTAssertGreaterThanOrEqual(points.count, 4)
        let start = points[0].pressure
        let mid = points[points.count / 2].pressure
        XCTAssertLessThan(start, mid, "Attack envelope should start lighter than mid-stroke")
    }

    func testStrokeEndPressureReleases() {
        let job = sampleStrokeJob()
        let config = HandwritingConfig(
            instrument: .ballpoint,
            variation: .off,
            seed: 7,
            applyGeometryVariation: false
        )
        let points = HandwritingSimulator.simulate(job: job, config: config)
        let mid = points[points.count / 2].pressure
        let end = points.last!.pressure
        XCTAssertLessThan(end, mid + 0.02, "Release envelope should lighten the finishing tail")
    }

    func testFountainStaysInSafeBand() {
        let job = sampleStrokeJob()
        let config = HandwritingConfig(instrument: .fountain, variation: .neat, seed: 99)
        let points = HandwritingSimulator.simulate(job: job, config: config)
        let pen = PenProfile.profile(for: .fountain)
        for p in points {
            XCTAssertLessThanOrEqual(p.pressure, pen.maxPressureSafety + 1e-9)
            XCTAssertGreaterThanOrEqual(p.pressure, 0)
        }
    }

    func testFilterLimitsPressureRate() {
        let pen = PenProfile.profile(for: .ballpoint)
        let arcs = [0.0, 1.0, 2.0, 3.0, 4.0]
        let raw = [0.2, 0.95, 0.2, 0.95, 0.2]
        let filtered = ServoPressureFilter.filter(pressures: raw, arcLengths: arcs, pen: pen)
        for i in 1..<filtered.count {
            let ds = arcs[i] - arcs[i - 1]
            XCTAssertLessThanOrEqual(
                abs(filtered[i] - filtered[i - 1]),
                pen.maxPressureDeltaPerMm * ds + 0.02,
                "Filtered Δp should respect rate limit (with tiny LP slack)"
            )
        }
    }

    func testLowFrequencyVariationIsSmooth() {
        let v = LowFrequencyVariation.targets(
            lengthMm: 40,
            amplitude: 0.03,
            wavelengthMm: 10...20,
            seed: 123
        )
        var prev = v.value(atS: 0)
        for s in stride(from: 0.5, through: 40, by: 0.5) {
            let cur = v.value(atS: s)
            XCTAssertLessThan(abs(cur - prev), 0.02, "LF variation must not jump point-to-point")
            prev = cur
        }
    }

    func testSeedReproducible() {
        let job = sampleStrokeJob()
        let a = HandwritingSimulator.simulate(
            job: job,
            config: HandwritingConfig(instrument: .gel, variation: .neat, seed: 42)
        )
        let b = HandwritingSimulator.simulate(
            job: job,
            config: HandwritingConfig(instrument: .gel, variation: .neat, seed: 42)
        )
        XCTAssertEqual(a.map(\.pressure), b.map(\.pressure))
        XCTAssertEqual(a.map(\.x), b.map(\.x))
    }

    func testDifferentSeedsDiffer() {
        let job = sampleStrokeJob()
        let a = HandwritingSimulator.simulate(
            job: job,
            config: HandwritingConfig(instrument: .gel, variation: .neat, seed: 1)
        )
        let b = HandwritingSimulator.simulate(
            job: job,
            config: HandwritingConfig(instrument: .gel, variation: .neat, seed: 2)
        )
        XCTAssertNotEqual(a.map(\.pressure), b.map(\.pressure))
    }

    func testGCodeContainsVariableZ() {
        let job = sampleStrokeJob()
        let gcode = HandwritingSimulator.gcode(
            job: job,
            profile: .ta4,
            config: HandwritingConfig(instrument: .ballpoint, variation: .off, seed: 3, applyGeometryVariation: false)
        )
        XCTAssertTrue(gcode.contains("G1"))
        let zLines = gcode.split(whereSeparator: \.isNewline).filter {
            $0.uppercased().contains("Z") && $0.uppercased().contains("G1")
        }
        XCTAssertGreaterThanOrEqual(zLines.count, 2)
    }

    func testEnrichPreservesStrokeCount() {
        let job = sampleStrokeJob()
        let enriched = HandwritingSimulator.enrich(
            job: job,
            config: HandwritingConfig(instrument: .ballpoint, variation: .off, seed: 1, applyGeometryVariation: false)
        )
        let moves = enriched.commands.filter {
            if case .move = $0 { return true }
            return false
        }
        XCTAssertEqual(moves.count, 1)
        let pressures = enriched.commands.compactMap { cmd -> Double? in
            if case .line(let p) = cmd { return p.pressure }
            return nil
        }
        XCTAssertEqual(pressures.count, 6)
        XCTAssertTrue(pressures.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testTextExamplePipeline() {
        let job = SingleLineText.plotJob(text: "Hi", heightMm: 10, origin: PlotPoint(x: 5, y: 40))
        let points = HandwritingSimulator.simulate(
            job: job,
            config: HandwritingConfig(instrument: .fountain, variation: .neat, seed: 11)
        )
        XCTAssertFalse(points.isEmpty)
        XCTAssertTrue(points.contains(where: { $0.penDown }))
        // Example JSON-shaped fields present
        let sample = points[min(3, points.count - 1)]
        XCTAssertGreaterThanOrEqual(sample.pressure, 0)
        XCTAssertLessThanOrEqual(sample.pressure, 1)
        XCTAssertGreaterThan(sample.feedMmMin, 0)
    }

    func testPenProfilesCoverRequestedBands() {
        let fountain = PenProfile.profile(for: .fountain)
        XCTAssertGreaterThanOrEqual(fountain.basePressure, 0.15)
        XCTAssertLessThanOrEqual(fountain.basePressure, 0.30)
        let ball = PenProfile.profile(for: .ballpoint)
        XCTAssertGreaterThanOrEqual(ball.basePressure, 0.45)
        XCTAssertLessThanOrEqual(ball.basePressure, 0.70)
    }
}
