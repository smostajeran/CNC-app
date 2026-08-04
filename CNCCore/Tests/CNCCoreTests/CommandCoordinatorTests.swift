import XCTest
@testable import CNCCore

final class CommandCoordinatorTests: XCTestCase {
    private func connectedClient() throws -> (GRBLSimulator, GRBLClient) {
        let sim = GRBLSimulator()
        let client = GRBLClient(transport: sim)
        client.timingScale = 0
        try client.connect(path: "/dev/sim", baudRate: 115_200)
        return (sim, client)
    }

    func testBlocksManualAndJogWhileStreaming() throws {
        let (_, client) = try connectedClient()
        let coord = CommandCoordinator(client: client)
        try coord.beginStreaming()
        XCTAssertEqual(coord.busyReason, .streaming)
        XCTAssertFalse(coord.allowsManualCommands)
        XCTAssertThrowsError(try coord.sendManualLine("G0 X0")) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .busy(.streaming))
        }
        XCTAssertThrowsError(try coord.jog(dx: 1, dy: 0, feed: 1000, machine: .ta4)) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .busy(.streaming))
        }
        // Realtime always allowed.
        XCTAssertNoThrow(try coord.feedHold())
        XCTAssertNoThrow(try coord.requestStatus())
        coord.endStreaming()
        XCTAssertNil(coord.busyReason)
        XCTAssertNoThrow(try coord.sendManualLine("G0 X0"))
        client.disconnect()
    }

    func testBlocksManualWhileWaitingForPenChange() throws {
        let (_, client) = try connectedClient()
        let coord = CommandCoordinator(client: client)
        try coord.beginStreaming()
        try coord.enterPenChangeWait()
        XCTAssertEqual(coord.busyReason, .waitingForPenChange)
        XCTAssertThrowsError(try coord.sendManualLine("G0 X0"))
        try coord.resumeStreamingAfterPenChange()
        XCTAssertEqual(coord.busyReason, .streaming)
        coord.endStreaming()
        client.disconnect()
    }

    func testSendJobLineOnlyWhileStreaming() throws {
        let (_, client) = try connectedClient()
        let coord = CommandCoordinator(client: client)
        XCTAssertThrowsError(try coord.sendJobLine("G0 X0")) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .notStreaming)
        }
        try coord.beginStreaming()
        XCTAssertNoThrow(try coord.sendJobLine("G0 X0"))
        coord.endStreaming()
        client.disconnect()
    }

    func testCalibratingAllowsJogButBlocksSecondJob() throws {
        let (_, client) = try connectedClient()
        let coord = CommandCoordinator(client: client)
        try coord.beginCalibrating()
        XCTAssertTrue(coord.allowsManualCommands)
        XCTAssertNoThrow(try coord.jog(dx: 1, dy: 0, feed: 800, machine: .ta4))
        XCTAssertThrowsError(try coord.beginStreaming()) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .busy(.calibrating))
        }
        coord.endCalibrating()
        XCTAssertNoThrow(try coord.beginStreaming())
        coord.endStreaming()
        client.disconnect()
    }

    func testNotConnectedBlocksManual() throws {
        let sim = GRBLSimulator()
        let client = GRBLClient(transport: sim)
        let coord = CommandCoordinator(client: client)
        XCTAssertThrowsError(try coord.sendManualLine("G0 X0")) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .notConnected)
        }
    }

    func testBeginStreamingTwiceIsBusy() throws {
        let (_, client) = try connectedClient()
        let coord = CommandCoordinator(client: client)
        try coord.beginStreaming()
        XCTAssertThrowsError(try coord.beginStreaming()) { err in
            XCTAssertEqual(err as? CommandCoordinatorError, .busy(.streaming))
        }
        coord.endStreaming()
        client.disconnect()
    }

    func testProbeSetsAndClearsBusy() throws {
        let (_, client) = try connectedClient()
        let coord = CommandCoordinator(client: client)
        var reasons: [MachineBusyReason?] = []
        coord.onBusyChange = { reasons.append($0) }
        let result = try coord.probe()
        XCTAssertTrue(result.buildInfo.contains("VER:1.1f") || result.settings["$130"] == 390)
        XCTAssertNil(coord.busyReason)
        XCTAssertTrue(reasons.contains(.probing))
        XCTAssertEqual(reasons.last ?? .probing, nil)
        client.disconnect()
    }
}
