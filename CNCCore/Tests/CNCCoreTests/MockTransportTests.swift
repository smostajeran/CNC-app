import XCTest
@testable import CNCCore

final class MockTransport: GRBLTransport {
    var isOpen = false
    var written: [Data] = []
    var readQueue: [Data] = []

    func open(path: String, baudRate: Int) throws {
        isOpen = true
    }

    func close() {
        isOpen = false
    }

    func write(_ data: Data) throws {
        written.append(data)
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("$I") {
            readQueue.append(Data("[VER:1.1f.20190825:].\nok\n".utf8))
        } else if text.contains("$$") {
            readQueue.append(Data("$100=80.000\n$130=390.000\n$131=200.000\nok\n".utf8))
        } else if data == Data([GRBLRealtime.softReset]) {
            readQueue.append(Data("Grbl 1.1f ['$' for help]\n".utf8))
        } else if data == Data([GRBLRealtime.status]) {
            readQueue.append(Data("<Idle|MPos:0.000,0.000,0.000|WCO:0.000,0.000,0.000|FS:0,0>\n".utf8))
        } else if text.hasSuffix("\n") {
            readQueue.append(Data("ok\n".utf8))
        }
    }

    func read(maxLength: Int, timeout: TimeInterval) throws -> Data {
        if readQueue.isEmpty { return Data() }
        return readQueue.removeFirst()
    }
}

final class GRBLClientProbeTests: XCTestCase {
    func testProbeParsesMockBoard() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        let result = try client.probe()
        XCTAssertTrue(result.buildInfo.contains("VER:1.1f") || result.settings["$130"] == 390)
        XCTAssertEqual(result.settings["$130"], 390)
        XCTAssertEqual(result.settings["$131"], 200)
        client.disconnect()
    }

    func testHomeXYLiftsPenThenSendsDollarH() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        transport.written.removeAll()
        try client.homeXY(machine: .ta4)
        let lines = transport.written.compactMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(lines.contains { $0.hasPrefix("G90 G0 Z") }, "pen should lift before seeking switches")
        XCTAssertTrue(lines.contains { $0 == "$H\n" || $0.hasPrefix("$H") }, "GRBL homing cycle")
        client.disconnect()
    }

    func testJogDoesNotHostNegateWhenInvertFlagsSet() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        var inverted = MachineProfile.ta4
        inverted.invertX = true
        inverted.invertY = true
        transport.written.removeAll()
        try client.jog(dx: 10, dy: 5, feed: 1000, machine: inverted)
        let lines = transport.written.compactMap { String(data: $0, encoding: .utf8) }
        let jog = lines.first { $0.contains("$J=") }
        XCTAssertEqual(jog, "$J=G91 G21 X10.000 Y5.000 F1000.000\n")
        XCTAssertFalse(jog?.contains("X-") == true, "host must not double-apply $3 invert")
        client.disconnect()
    }

    func testCoordinatorHomeXYBlockedWhenStreaming() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        let coord = CommandCoordinator(client: client)
        try coord.beginStreaming()
        XCTAssertThrowsError(try coord.homeXY(machine: .ta4)) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .busy(.streaming))
        }
        coord.endStreaming()
        XCTAssertNoThrow(try coord.homeXY(machine: .ta4))
        client.disconnect()
    }

    func testUnlockSoftResetsThenSendsDollarX() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        transport.written.removeAll()
        try client.unlock()
        XCTAssertTrue(transport.written.contains(Data([GRBLRealtime.softReset])), "unlock should soft-reset when not already Alarm")
        let lines = transport.written.compactMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(lines.contains { $0 == "$X\n" || $0.hasPrefix("$X") }, "unlock should send $X")
        XCTAssertTrue(transport.written.contains(Data([GRBLRealtime.status])), "unlock should request status")
        client.disconnect()
    }

    func testUnlockWhenAlreadyAlarmSendsDollarXWithoutSoftReset() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        // Simulate post E-Stop ALARM:3 status.
        transport.readQueue.append(Data("<Alarm|MPos:0.000,0.000,0.000|FS:0,0>\n".utf8))
        Thread.sleep(forTimeInterval: 0.15)
        transport.written.removeAll()
        try client.unlock()
        XCTAssertFalse(
            transport.written.contains(Data([GRBLRealtime.softReset])),
            "already-Alarm unlock must not soft-reset (that re-triggers ALARM:3)"
        )
        let lines = transport.written.compactMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(lines.contains { $0 == "$X\n" || $0.hasPrefix("$X") })
        client.disconnect()
    }

    func testCoordinatorUnlockAllowedWhileStreamingAndClearsBusy() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        let coord = CommandCoordinator(client: client)
        try coord.beginStreaming()
        XCTAssertEqual(coord.busyReason, .streaming)
        XCTAssertNoThrow(try coord.unlock())
        XCTAssertNil(coord.busyReason, "unlock must clear job ownership after controller reset")
        client.disconnect()
    }

    func testCoordinatorUnlockAllowedWhileProbing() throws {
        let transport = MockTransport()
        let client = GRBLClient(transport: transport)
        try client.connect(path: "/dev/mock", baudRate: 115_200)
        let coord = CommandCoordinator(client: client)
        try coord.beginProbing()
        XCTAssertNoThrow(try coord.unlock())
        XCTAssertNil(coord.busyReason)
        client.disconnect()
    }
}
