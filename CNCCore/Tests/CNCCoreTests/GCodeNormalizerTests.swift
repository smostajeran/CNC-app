import XCTest
@testable import CNCCore

final class GCodeNormalizerTests: XCTestCase {
    func testMapsServoPenCommands() {
        let input = """
        G0 X0 Y0
        M3 S90
        G1 X10
        M5
        SM03 S40
        M30
        """
        let result = GCodeNormalizer.normalizePenCommands(input, profile: .ta4)
        XCTAssertEqual(result.substitutions, 3)
        XCTAssertTrue(result.text.contains("G1 Z"))
        XCTAssertTrue(result.text.contains("G0 Z"))
        XCTAssertTrue(result.text.contains("M30"))
        XCTAssertFalse(result.text.uppercased().contains("\nM3 "))
        XCTAssertFalse(result.text.uppercased().contains("SM03"))
    }
}
