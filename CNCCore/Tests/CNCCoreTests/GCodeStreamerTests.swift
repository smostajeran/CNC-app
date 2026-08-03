import XCTest
@testable import CNCCore

final class GCodeStreamerTests: XCTestCase {
    func testNormalizeStripsComments() {
        let lines = GCodeStreamer.normalize("""
        G0 X0 ; comment
        (block comment)
        G1 Y1
        """)
        XCTAssertEqual(lines, ["G0 X0", "G1 Y1"])
    }

    func testAckBasedProgressAndCompletion() {
        let s = GCodeStreamer()
        s.requireIdleForCompletion = false
        s.load(lines: ["G0 X0", "G0 Y1", "M2"])
        s.start()

        XCTAssertEqual(s.nextLineToSend(), "G0 X0")
        XCTAssertEqual(s.nextLineToSend(), "G0 Y1")
        XCTAssertEqual(s.nextLineToSend(), "M2")
        XCTAssertNil(s.nextLineToSend())
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
        s.handleResponse("ok")
        XCTAssertEqual(s.progress, 1.0 / 3.0, accuracy: 0.001)
        s.handleResponse("ok")
        s.handleResponse("ok")
        XCTAssertEqual(s.state, .completed)
        XCTAssertEqual(s.progress, 1.0, accuracy: 0.001)
    }

    func testCompletionWaitsForIdleWhenRequired() {
        let s = GCodeStreamer()
        s.requireIdleForCompletion = true
        s.load(lines: ["G0 X0"])
        s.start()
        _ = s.nextLineToSend()
        s.handleResponse("ok")
        XCTAssertTrue(s.awaitingIdleForCompletion)
        XCTAssertNotEqual(s.state, .completed)
        s.noteMachineIdle()
        XCTAssertEqual(s.state, .completed)
    }

    func testM0DrainsThenWaitsForResume() {
        let s = GCodeStreamer()
        s.requireIdleForCompletion = false
        s.load(lines: ["G0 X0", "M0", "G0 X10"])
        s.start()
        XCTAssertEqual(s.nextLineToSend(), "G0 X0")
        // M0 must wait until prior ok drains.
        XCTAssertNil(s.nextLineToSend())
        s.handleResponse("ok")
        XCTAssertEqual(s.nextLineToSend(), "M0")
        XCTAssertNil(s.nextLineToSend())
        s.handleResponse("ok")
        XCTAssertEqual(s.state, .waitingForPenChange)
        XCTAssertNil(s.nextLineToSend())
        s.resume()
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.nextLineToSend(), "G0 X10")
    }

    func testCharacterWindowBlocksWhenFull() {
        let s = GCodeStreamer()
        let long = String(repeating: "A", count: 60)
        s.load(lines: [long, long, long])
        s.start()
        XCTAssertNotNil(s.nextLineToSend())
        XCTAssertNotNil(s.nextLineToSend())
        XCTAssertNil(s.nextLineToSend())
        XCTAssertGreaterThan(s.bytesInFlight, 0)
        s.handleResponse("ok")
        XCTAssertNotNil(s.nextLineToSend())
    }

    func testErrorFaultsStreamer() {
        let s = GCodeStreamer()
        s.load(lines: ["G0 X0"])
        s.start()
        _ = s.nextLineToSend()
        s.handleResponse("error:20")
        XCTAssertEqual(s.state, .fault("error:20"))
    }

    func testCancel() {
        let s = GCodeStreamer()
        s.load(lines: ["G0 X0", "G0 Y1"])
        s.start()
        _ = s.nextLineToSend()
        s.cancel()
        XCTAssertEqual(s.state, .cancelled)
        XCTAssertNil(s.nextLineToSend())
    }
}
