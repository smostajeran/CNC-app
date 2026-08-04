import XCTest
@testable import CNCCore

final class JobPreflightTests: XCTestCase {
    func testParserTracksBoundsAndPenChange() {
        let gcode = """
        G21
        G90
        G0 Z5
        G0 X10 Y10
        G1 Z0 F1500
        G1 X50 Y10
        M0
        G1 X50 Y40
        G0 Z5
        """
        let parse = GCodeParser.parse(gcode)
        XCTAssertEqual(parse.penChangeCount, 1)
        XCTAssertEqual(parse.bounds.minX, 10, accuracy: 0.01)
        XCTAssertEqual(parse.bounds.maxX, 50, accuracy: 0.01)
        XCTAssertEqual(parse.bounds.maxY, 40, accuracy: 0.01)
        XCTAssertFalse(parse.plotJob.commands.isEmpty)
    }

    func testPreflightRejectsOutOfBounds() {
        let gcode = """
        G21
        G90
        G0 X0 Y0
        G1 X500 Y10 F1000
        """
        let report = JobPreflight.assess(gcode: gcode, profile: .ta4, workZeroKnown: true)
        XCTAssertFalse(report.okToStart)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("exceed") })
    }

    func testPreflightAllowsInBedJob() {
        let gcode = """
        G21
        G90
        G0 Z5
        G0 X10 Y10
        G1 Z0 F1500
        G1 X20 Y10
        G0 Z5
        """
        let report = JobPreflight.assess(gcode: gcode, profile: .ta4, machineState: "Idle", workZeroKnown: true)
        XCTAssertTrue(report.okToStart)
    }

    func testFrameGCodeStaysPenUp() {
        let bounds = PlotBounds(minX: 5, minY: 5, maxX: 40, maxY: 30)
        let g = JobPreflight.frameGCode(bounds: bounds, profile: .ta4)
        XCTAssertTrue(g.contains("G0 Z"))
        XCTAssertFalse(g.uppercased().contains("G1 Z0"))
        XCTAssertTrue(g.contains("X40"))
    }

    func testCommandCoordinatorBlocksManualWhileStreaming() throws {
        // Kept as a smoke check; fuller coverage lives in CommandCoordinatorTests.
        let transport = GRBLSimulator()
        let client = GRBLClient(transport: transport)
        client.timingScale = 0
        try client.connect(path: "/dev/sim", baudRate: 115_200)
        let coord = CommandCoordinator(client: client)
        try coord.beginStreaming()
        XCTAssertThrowsError(try coord.sendManualLine("G0 X0")) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .busy(.streaming))
        }
        coord.endStreaming()
        XCTAssertNoThrow(try coord.sendManualLine("G0 X0"))
        client.disconnect()
    }
}
