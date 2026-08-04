import XCTest
@testable import CNCCore

final class JobRunnerTests: XCTestCase {
    private func makeStack() throws -> (GRBLSimulator, GRBLClient, CommandCoordinator, JobRunner) {
        let sim = GRBLSimulator()
        let client = GRBLClient(transport: sim)
        client.timingScale = 0
        try client.connect(path: "/dev/sim", baudRate: 115_200)
        let coord = CommandCoordinator(client: client)
        let runner = JobRunner()
        runner.attach(coordinator: coord, client: client)
        return (sim, client, coord, runner)
    }

    func testShortJobCompletesWithIdleGate() throws {
        let (_, client, coord, runner) = try makeStack()
        runner.streamer.requireIdleForCompletion = true

        let done = expectation(description: "completed")
        runner.onState = { state in
            if state == .completed { done.fulfill() }
        }

        runner.loadGCode("G0 X0\nG0 X1\n")
        try runner.start()
        XCTAssertEqual(coord.busyReason, .streaming)

        wait(for: [done], timeout: 3.0)
        XCTAssertEqual(runner.streamer.state, .completed)
        XCTAssertNil(coord.busyReason)
        client.disconnect()
    }

    func testPauseAndResumeSendRealtimeBytes() throws {
        let (sim, client, _, runner) = try makeStack()
        runner.streamer.requireIdleForCompletion = false
        runner.loadGCode("G0 X0\nG0 X1\nG0 X2\nG0 X3\n")
        try runner.start()

        // Let a couple of lines go out, then pause.
        Thread.sleep(forTimeInterval: 0.05)
        sim.resetHistory()
        runner.pause()
        XCTAssertEqual(runner.streamer.state, .paused)
        XCTAssertTrue(sim.realtimeBytes.contains(GRBLRealtime.feedHold))

        sim.resetHistory()
        runner.resume()
        XCTAssertEqual(runner.streamer.state, .running)
        XCTAssertTrue(sim.realtimeBytes.contains(GRBLRealtime.cycleStart))

        let done = expectation(description: "completed after resume")
        runner.onState = { if $0 == .completed { done.fulfill() } }
        wait(for: [done], timeout: 3.0)
        client.disconnect()
    }

    func testCancelEndsStreamingOwnership() throws {
        let (_, client, coord, runner) = try makeStack()
        runner.streamer.requireIdleForCompletion = false
        runner.loadGCode("G0 X0\nG0 X1\nG0 X2\n")
        try runner.start()
        XCTAssertEqual(coord.busyReason, .streaming)
        runner.cancel()
        XCTAssertEqual(runner.streamer.state, .cancelled)
        XCTAssertNil(coord.busyReason)
        client.disconnect()
    }

    func testM0PenChangePauseAndResume() throws {
        let (_, client, coord, runner) = try makeStack()
        runner.streamer.requireIdleForCompletion = false

        let pen = expectation(description: "pen change")
        let done = expectation(description: "completed")
        runner.onPenChange = { pen.fulfill() }
        runner.onState = { if $0 == .completed { done.fulfill() } }

        runner.loadGCode("G0 X0\nM0\nG0 X10\n")
        try runner.start()

        wait(for: [pen], timeout: 3.0)
        XCTAssertEqual(runner.streamer.state, .waitingForPenChange)
        XCTAssertEqual(coord.busyReason, .waitingForPenChange)
        XCTAssertThrowsError(try coord.sendManualLine("G0 Y0"))

        runner.resume()
        wait(for: [done], timeout: 3.0)
        XCTAssertEqual(runner.streamer.state, .completed)
        XCTAssertNil(coord.busyReason)
        client.disconnect()
    }

    func testSendFailureFaultsAndReleasesCoordinator() throws {
        let (sim, client, coord, runner) = try makeStack()
        runner.streamer.requireIdleForCompletion = false

        let faulted = expectation(description: "fault")
        runner.onState = { state in
            if case .fault = state { faulted.fulfill() }
        }

        // Many lines so the job cannot finish before we inject a write failure.
        let gcode = (0..<40).map { "G0 X\($0)" }.joined(separator: "\n")
        runner.loadGCode(gcode)
        try runner.start()
        sim.failWrites = true

        wait(for: [faulted], timeout: 2.0)
        XCTAssertNil(coord.busyReason)
        client.disconnect()
    }
}
