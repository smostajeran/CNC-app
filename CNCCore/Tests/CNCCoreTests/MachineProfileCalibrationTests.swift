import XCTest
@testable import CNCCore

final class MachineProfileCalibrationTests: XCTestCase {
    func testCorrectedStepsPerMmScalesByCommandedOverMeasured() {
        let corrected = MachineProfile.correctedStepsPerMm(
            current: 80,
            commandedMm: 100,
            measuredMm: 95
        )
        XCTAssertEqual(corrected!, 80 * (100 / 95), accuracy: 0.0001)
    }

    func testCorrectedStepsPerMmRejectsBadInput() {
        XCTAssertNil(MachineProfile.correctedStepsPerMm(current: 80, commandedMm: 100, measuredMm: 0))
        XCTAssertNil(MachineProfile.correctedStepsPerMm(current: 0, commandedMm: 100, measuredMm: 100))
    }
}
