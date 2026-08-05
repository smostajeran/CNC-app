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
        var profile = MachineProfile.ta4
        profile.softLimitsEnabled = true
        let report = JobPreflight.assess(
            gcode: gcode,
            profile: profile,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true,
            machinePosition: SIMD3(0, 0, 0),
            workPosition: SIMD3(0, 0, 0),
            requireSoftLimits: true
        )
        XCTAssertTrue(report.okToStart)
    }

    func testPreflightBlocksStartWithoutHome() {
        let gcode = """
        G21
        G90
        G0 X10 Y10
        """
        let report = JobPreflight.assess(
            gcode: gcode,
            profile: .ta4,
            machineState: "Idle",
            requireHomed: true,
            isHomed: false
        )
        XCTAssertFalse(report.okToStart)
        XCTAssertTrue(report.issues.contains { $0.message.contains("Home X/Y") })
    }

    func testPreflightBlocksWhenWorkOffsetPushesPastTravel() {
        // Work path fits 390×200, but G54 origin at machine (100,50) pushes max Y to 210.
        let gcode = """
        G21
        G90
        G0 X10 Y10
        G1 X50 Y160 F1000
        """
        var profile = MachineProfile.ta4
        profile.softLimitsEnabled = true
        let report = JobPreflight.assess(
            gcode: gcode,
            profile: profile,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true,
            machinePosition: SIMD3(100, 50, 0),
            workPosition: SIMD3(0, 0, 0),
            requireSoftLimits: true
        )
        XCTAssertFalse(report.okToStart)
        XCTAssertTrue(report.issues.contains { $0.message.contains("work offset") })
    }

    func testPreflightBlocksWhenSoftLimitsOff() {
        let gcode = """
        G21
        G90
        G0 X10 Y10
        """
        var profile = MachineProfile.ta4
        profile.softLimitsEnabled = false
        let report = JobPreflight.assess(
            gcode: gcode,
            profile: profile,
            machineState: "Idle",
            requireHomed: true,
            isHomed: true,
            requireSoftLimits: true
        )
        XCTAssertFalse(report.okToStart)
        XCTAssertTrue(report.issues.contains { $0.message.contains("$20") })
    }

    func testMotionSafetyMachineBounds() {
        let work = PlotBounds(minX: 0, minY: 0, maxX: 100, maxY: 80)
        let machine = MotionSafety.machineBounds(workBounds: work, offsetX: 20, offsetY: 10)
        XCTAssertEqual(machine.minX, 20, accuracy: 0.001)
        XCTAssertEqual(machine.maxY, 90, accuracy: 0.001)
        XCTAssertTrue(MotionSafety.fitsTravel(machine, travelX: 390, travelY: 200))
        XCTAssertFalse(MotionSafety.fitsTravel(machine, travelX: 390, travelY: 85))
    }

    func testFrameGCodeStaysPenUp() {
        let bounds = PlotBounds(minX: 5, minY: 5, maxX: 40, maxY: 30)
        let g = JobPreflight.frameGCode(bounds: bounds, profile: .ta4)
        XCTAssertTrue(g.contains("G0 Z"))
        XCTAssertFalse(g.uppercased().contains("G1 Z0"))
        XCTAssertTrue(g.contains("X40"))
    }

    func testPreflightBlocksG28AndArcs() {
        let g28 = JobPreflight.assess(
            gcode: "G21\nG90\nG28\nG0 X10 Y10\n",
            profile: .ta4,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true
        )
        XCTAssertFalse(g28.okToStart)
        XCTAssertTrue(g28.issues.contains { $0.severity == .error && $0.message.contains("G28") })

        let arc = JobPreflight.assess(
            gcode: "G21\nG90\nG2 X20 Y10 I5 J0 F1000\n",
            profile: .ta4,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true
        )
        XCTAssertFalse(arc.okToStart)
        XCTAssertTrue(arc.issues.contains { $0.severity == .error && $0.message.uppercased().contains("G2") })
    }

    func testPreflightBlocksAlternateWCS() {
        let report = JobPreflight.assess(
            gcode: "G21\nG90\nG55\nG0 X10 Y10\n",
            profile: .ta4,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true
        )
        XCTAssertFalse(report.okToStart)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("G55") })
    }

    func testPreflightBlocksUnreliableStatusOffset() {
        var profile = MachineProfile.ta4
        profile.softLimitsEnabled = true
        let status = GRBLStatus.parse("<Idle|MPos:0.000,0.000,0.000|FS:0,0>")!
        let report = JobPreflight.assess(
            gcode: "G21\nG90\nG0 X10 Y10\n",
            profile: profile,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true,
            status: status,
            requireSoftLimits: true
        )
        XCTAssertFalse(report.okToStart)
        XCTAssertTrue(report.issues.contains { $0.message.contains("WCO") })
    }

    func testPreflightAllowsReliableWCOStatus() {
        var profile = MachineProfile.ta4
        profile.softLimitsEnabled = true
        let status = GRBLStatus.parse("<Idle|MPos:0.000,0.000,0.000|WCO:0.000,0.000,0.000|FS:0,0>")!
        let report = JobPreflight.assess(
            gcode: "G21\nG90\nG0 Z5\nG0 X10 Y10\nG1 Z0 F1500\nG1 X20 Y10\nG0 Z5\n",
            profile: profile,
            machineState: "Idle",
            workZeroKnown: true,
            requireHomed: true,
            isHomed: true,
            status: status,
            requireSoftLimits: true
        )
        XCTAssertTrue(report.okToStart, report.issues.map(\.message).joined(separator: "; "))
    }

    func testCommandCoordinatorBlocksManualWhileStreaming() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
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
