import XCTest
@testable import CNCCore

final class GRBLStatusPinTests: XCTestCase {
    func testParsesLimitPins() {
        let status = GRBLStatus.parse("<Idle|MPos:1.000,2.000,3.000|Pn:XY|FS:0,0>")
        XCTAssertNotNil(status)
        XCTAssertTrue(status!.pins.x)
        XCTAssertTrue(status!.pins.y)
        XCTAssertFalse(status!.pins.z)
    }

    func testAbsentPinsMeansClear() {
        let status = GRBLStatus.parse("<Idle|MPos:0.000,0.000,0.000|FS:0,0>")
        XCTAssertNotNil(status)
        XCTAssertFalse(status!.pins.anyXYLimit)
    }

    func testWPosStillParses() {
        let status = GRBLStatus.parse("<Idle|WPos:4.000,5.000,6.000|Pn:X>")
        XCTAssertEqual(status?.wpos.x ?? -1, 4, accuracy: 0.001)
        XCTAssertTrue(status?.pins.x == true)
        XCTAssertFalse(status?.pins.y == true)
    }
}
