import XCTest
@testable import CNCCore

final class SVGToGCodeTests: XCTestCase {
    func testRectFitsWorkspace() throws {
        let url = Bundle.module.url(forResource: "square", withExtension: "svg", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "square", withExtension: "svg")
        XCTAssertNotNil(url)
        let svg = try String(contentsOf: url!, encoding: .utf8)
        let profile = MachineProfile.ta4
        let job = try SVGToGCode.plotJob(from: svg, profile: profile, fitToWorkspace: true)

        XCTAssertFalse(job.commands.isEmpty)
        XCTAssertLessThanOrEqual(job.bounds.maxX, profile.travelX + 0.01)
        XCTAssertLessThanOrEqual(job.bounds.maxY, profile.travelY + 0.01)
        XCTAssertGreaterThanOrEqual(job.bounds.minX, -0.01)
        XCTAssertGreaterThanOrEqual(job.bounds.minY, -0.01)

        let gcode = SVGToGCode.gcode(from: job, profile: profile)
        XCTAssertTrue(gcode.contains("G0 Z"))
        XCTAssertTrue(gcode.contains("G1 X"))
        XCTAssertTrue(gcode.contains("M2"))
    }

    func testPathDParse() {
        let cmds = SVGToGCode.parsePathD("M0 0 L10 0 L10 10 Z")
        XCTAssertEqual(cmds.first, .move(PlotPoint(x: 0, y: 0)))
        XCTAssertTrue(cmds.contains(.line(PlotPoint(x: 10, y: 0))))
        XCTAssertTrue(cmds.contains(.line(PlotPoint(x: 10, y: 10))))
        XCTAssertTrue(cmds.contains(.line(PlotPoint(x: 0, y: 0))))
    }

    func testStatusParse() {
        let status = GRBLStatus.parse("<Idle|MPos:1.000,2.000,3.000|FS:0,0>")
        XCTAssertEqual(status?.state, "Idle")
        XCTAssertEqual(status?.mpos.x, 1)
        XCTAssertEqual(status?.mpos.y, 2)
        XCTAssertEqual(status?.mpos.z, 3)
    }

    func testSettingsParse() {
        let text = """
        $100=80.000
        $130=390.000
        $131=200.000
        ok
        """
        let settings = GRBLProbeResult.parseSettings(text)
        XCTAssertEqual(settings["$100"], 80)
        XCTAssertEqual(settings["$130"], 390)
        XCTAssertEqual(settings["$131"], 200)

        var profile = MachineProfile.ta4
        profile.applyGRBLSettings(settings)
        XCTAssertEqual(profile.travelX, 390)
        XCTAssertEqual(profile.travelY, 200)
        XCTAssertEqual(profile.stepsPerMmX, 80)
    }
}
