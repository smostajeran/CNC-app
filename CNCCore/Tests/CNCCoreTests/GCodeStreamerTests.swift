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

    func testOkPacedStreamingStillWorksForSingleLine() {
        let s = GCodeStreamer()
        s.load(lines: ["G0 X0", "G0 Y1", "M2"])
        s.start()

        XCTAssertEqual(s.nextLineToSend(), "G0 X0")
        // Still room in 127-byte window for more short lines
        XCTAssertEqual(s.nextLineToSend(), "G0 Y1")
        XCTAssertEqual(s.nextLineToSend(), "M2")
        XCTAssertNil(s.nextLineToSend())
        s.handleResponse("ok")
        s.handleResponse("ok")
        s.handleResponse("ok")
        XCTAssertEqual(s.state, .completed)
        XCTAssertEqual(s.progress, 1.0, accuracy: 0.001)
    }

    func testCharacterWindowBlocksWhenFull() {
        let s = GCodeStreamer()
        // Each line ~60 bytes + newline → only two fit in 127
        let long = String(repeating: "A", count: 60)
        s.load(lines: [long, long, long])
        s.start()
        XCTAssertNotNil(s.nextLineToSend())
        XCTAssertNotNil(s.nextLineToSend())
        XCTAssertNil(s.nextLineToSend()) // buffer full
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
