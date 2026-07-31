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

    func testOkPacedStreaming() {
        let s = GCodeStreamer()
        s.load(lines: ["G0 X0", "G0 Y1", "M2"])
        s.start()

        XCTAssertEqual(s.nextLineToSend(), "G0 X0")
        XCTAssertNil(s.nextLineToSend()) // waiting for ok
        s.handleResponse("ok")
        XCTAssertEqual(s.nextLineToSend(), "G0 Y1")
        s.handleResponse("ok")
        XCTAssertEqual(s.nextLineToSend(), "M2")
        s.handleResponse("ok")
        XCTAssertEqual(s.state, .completed)
        XCTAssertEqual(s.progress, 1.0, accuracy: 0.001)
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
