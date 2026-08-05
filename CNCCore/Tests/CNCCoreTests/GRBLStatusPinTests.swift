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

    func testMPosWithWCODerivesWPos() {
        let status = GRBLStatus.parse("<Idle|MPos:100.000,50.000,0.000|WCO:10.000,5.000,0.000|FS:0,0>")
        XCTAssertNotNil(status)
        XCTAssertTrue(status!.hasReliableWorkOffset)
        XCTAssertEqual(status!.wpos.x, 90, accuracy: 0.001)
        XCTAssertEqual(status!.wpos.y, 45, accuracy: 0.001)
        XCTAssertEqual(status!.wco.x, 10, accuracy: 0.001)
        let offset = MotionSafety.workOffset(from: status!)
        XCTAssertEqual(offset?.x ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(offset?.y ?? -1, 5, accuracy: 0.001)
    }

    func testWPosWithWCODerivesMPos() {
        let status = GRBLStatus.parse("<Idle|WPos:20.000,30.000,0.000|WCO:5.000,2.000,0.000|FS:0,0>")
        XCTAssertNotNil(status)
        XCTAssertTrue(status!.hasReliableWorkOffset)
        XCTAssertEqual(status!.mpos.x, 25, accuracy: 0.001)
        XCTAssertEqual(status!.mpos.y, 32, accuracy: 0.001)
    }

    func testMPosOnlyIsNotReliableOffset() {
        let status = GRBLStatus.parse("<Idle|MPos:1.000,2.000,3.000|FS:0,0>")
        XCTAssertNotNil(status)
        XCTAssertFalse(status!.hasReliableWorkOffset)
        XCTAssertNil(MotionSafety.workOffset(from: status!))
    }
}
