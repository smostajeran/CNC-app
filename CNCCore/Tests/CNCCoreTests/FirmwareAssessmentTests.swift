import XCTest
@testable import CNCCore

final class FirmwareAssessmentTests: XCTestCase {
    func testCompatible11f() {
        let a = FirmwareAssessment.assess(
            buildInfo: "[VER:1.1f.20190825:]",
            banner: "Grbl 1.1f ['$' for help]",
            settings: ["$130": 390, "$131": 200, "$32": 0]
        )
        XCTAssertEqual(a.verdict, .compatible)
        XCTAssertEqual(a.versionLabel, "1.1f")
    }

    func testCaution11z() {
        let a = FirmwareAssessment.assess(
            buildInfo: "[VER:1.1z.20190301:]",
            banner: "Grbl 1.1z ['$' for help]"
        )
        XCTAssertEqual(a.verdict, .caution)
        XCTAssertTrue(a.summary.lowercased().contains("1.1z"))
    }

    func testLaserModeCaution() {
        let a = FirmwareAssessment.assess(
            buildInfo: "[VER:1.1f.20190825:]",
            settings: ["$32": 1, "$130": 390, "$131": 200]
        )
        XCTAssertEqual(a.verdict, .caution)
        XCTAssertTrue(a.notes.contains(where: { $0.contains("laser mode") }))
    }

    func testUnknownEmpty() {
        let a = FirmwareAssessment.assess(buildInfo: "", banner: "")
        XCTAssertEqual(a.verdict, .unknown)
    }
}
