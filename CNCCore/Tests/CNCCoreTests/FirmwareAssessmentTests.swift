import XCTest
@testable import CNCCore

final class FirmwareAssessmentTests: XCTestCase {
    func testCompatibleGRBL11() {
        let a = FirmwareAssessment.assess(buildInfo: "[VER:1.1f.20190825:]", banner: "Grbl 1.1f ['$' for help]")
        XCTAssertEqual(a.verdict, .compatible)
        XCTAssertEqual(a.versionLabel, "1.1f")
    }

    func testVendorZIsCaution() {
        let a = FirmwareAssessment.assess(buildInfo: "[VER:1.1z.20200101:]")
        XCTAssertEqual(a.verdict, .caution)
    }

    func testEmptyIsUnknown() {
        let a = FirmwareAssessment.assess(buildInfo: "")
        XCTAssertEqual(a.verdict, .unknown)
    }
}
