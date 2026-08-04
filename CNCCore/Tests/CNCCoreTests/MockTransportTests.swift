import XCTest
@testable import CNCCore

final class GRBLClientProbeTests: XCTestCase {
    func testProbeParsesSimulatedBoard() throws {
        let transport = GRBLSimulator()
        let client = GRBLClient(transport: transport)
        client.timingScale = 0
        try client.connect(path: "/dev/sim", baudRate: 115_200)
        let result = try client.probe()
        XCTAssertTrue(result.buildInfo.contains("VER:1.1f") || result.settings["$130"] == 390)
        XCTAssertEqual(result.settings["$130"], 390)
        XCTAssertEqual(result.settings["$131"], 200)
        client.disconnect()
    }
}
