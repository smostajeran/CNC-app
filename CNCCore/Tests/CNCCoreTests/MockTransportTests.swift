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
}
