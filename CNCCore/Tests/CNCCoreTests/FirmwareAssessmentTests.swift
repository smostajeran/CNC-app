import XCTest
@testable import CNCCore

final class FirmwareAssessmentTests: XCTestCase {
    func testCompatibleGRBL11() {
        let a = FirmwareAssessment.assess(buildInfo: "[VER:1.1f.20190825:]", banner: "Grbl 1.1f ['$' for help]")
        XCTAssertEqual(a.verdict, .compatible)
        XCTAssertEqual(a.versionLabel, "1.1f")
    }

    func testCompatibleUppercaseVersionLetter() {
        let a = FirmwareAssessment.assess(buildInfo: "[VER:1.1F.20190825:]")
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

    func testSettingsInferGRBL11WhenVersionMissing() {
        let settings: [String: Double] = [
            "$100": 80, "$101": 80, "$110": 2000, "$111": 2000,
            "$130": 297, "$131": 200
        ]
        let a = FirmwareAssessment.assess(
            buildInfo: "[VER:]",
            banner: "Grbl ['$' for help]",
            settings: settings
        )
        XCTAssertEqual(a.verdict, .compatible)
        XCTAssertTrue(a.versionLabel.contains("1.1"))
        XCTAssertTrue(a.notes.contains(where: { $0.contains("A4 landscape") }))
    }

    func testA4TravelNote() {
        let notes = FirmwareAssessment.travelNotes(settings: ["$130": 297, "$131": 200])
        XCTAssertTrue(notes.first?.contains("A4 landscape") == true)
    }

    func testUnclearWithoutSettingsStaysCaution() {
        let a = FirmwareAssessment.assess(buildInfo: "[VER:]", banner: "Grbl ['$' for help]")
        XCTAssertEqual(a.verdict, .caution)
        XCTAssertTrue(a.summary.contains("unclear"))
    }
}
