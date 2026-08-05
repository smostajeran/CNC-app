import XCTest
@testable import CNCCore

final class PressureTests: XCTestCase {
    func testPressureMapsLightToHardZ() {
        var profile = MachineProfile.ta4
        profile.penDownZ = 0
        profile.pressureMinZ = 1.5
        profile.pressureMaxZ = 0
        profile.clampPressureRange()

        XCTAssertEqual(profile.z(forPressure: 0), profile.pressureMinZ, accuracy: 0.001)
        XCTAssertEqual(profile.z(forPressure: 1), profile.pressureMaxZ, accuracy: 0.001)
        XCTAssertGreaterThan(profile.z(forPressure: 0), profile.z(forPressure: 1))
        let mid = profile.z(forPressure: 0.5)
        XCTAssertEqual(mid, (profile.pressureMinZ + profile.pressureMaxZ) / 2, accuracy: 0.001)
    }

    func testHardZClampedToSoftFloor() {
        var profile = MachineProfile.ta4
        profile.penDownZ = 0
        profile.pressureMaxZ = -5
        profile.clampPressureRange()
        XCTAssertGreaterThanOrEqual(profile.pressureMaxZ, 0)
    }

    func testGCodeEmitsZOnPressureChange() {
        let profile = MachineProfile(
            penDownZ: 0,
            pressureMinZ: 1.5,
            pressureMaxZ: 0
        )
        let job = PlotJob(commands: [
            .move(PlotPoint(x: 0, y: 0)),
            .line(PlotPoint(x: 10, y: 0, pressure: 0.0)),
            .line(PlotPoint(x: 20, y: 0, pressure: 0.02)), // within epsilon — no new Z
            .line(PlotPoint(x: 30, y: 0, pressure: 1.0)),
        ])
        let gcode = SVGToGCode.gcode(from: job, profile: profile)
        let zLines = gcode.split(whereSeparator: \.isNewline).filter { $0.uppercased().contains("Z") && $0.uppercased().contains("G1") }
        // Initial pen down + hard pressure step (skip tiny epsilon change)
        XCTAssertGreaterThanOrEqual(zLines.count, 2)
        XCTAssertTrue(gcode.contains("Z1.500") || gcode.contains(String(format: "Z%.3f", profile.pressureMinZ)))
        XCTAssertTrue(gcode.contains("Z0.000") || gcode.contains(String(format: "Z%.3f", profile.pressureMaxZ)))
    }

    func testSVGStrokeWidthMapsToPressure() throws {
        let svg = """
        <svg viewBox="0 0 100 100">
          <path stroke-width="0.5" d="M0 0 L10 0"/>
          <path stroke-width="2.0" d="M0 10 L10 10"/>
        </svg>
        """
        let job = try SVGToGCode.plotJob(from: svg, profile: .ta4, fitToWorkspace: false)
        let pressures = job.commands.compactMap { cmd -> Double? in
            if case .line(let p) = cmd { return p.pressure }
            return nil
        }
        XCTAssertFalse(pressures.isEmpty)
        XCTAssertEqual(pressures.min() ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(pressures.max() ?? 0, 1, accuracy: 0.001)
    }

    func testInkDocumentRoundTrip() throws {
        var doc = InkDocument(travelX: 390, travelY: 200)
        doc.strokes = [
            InkDocument.Stroke(samples: [
                .init(x: 10, y: 20, pressure: 0.2),
                .init(x: 30, y: 40, pressure: 0.9),
            ])
        ]
        let data = try doc.jsonData()
        let loaded = try InkDocument.load(from: data)
        XCTAssertEqual(loaded.strokes.count, 1)
        XCTAssertEqual(loaded.strokes[0].samples[1].pressure, 0.9, accuracy: 0.001)

        let job = loaded.plotJob()
        XCTAssertEqual(job.commands.first, .move(PlotPoint(x: 10, y: 20, pressure: 0.2)))
        let gcode = loaded.gcode(profile: .ta4)
        XCTAssertTrue(gcode.contains("G1"))
        XCTAssertTrue(gcode.contains("Z"))
    }

    func testSyntheticPressureFasterIsLighter() {
        let slow = InkCapture.syntheticPressure(distanceMm: 1, dt: 0.05)
        let fast = InkCapture.syntheticPressure(distanceMm: 20, dt: 0.05)
        XCTAssertGreaterThan(slow, fast)
    }
}
