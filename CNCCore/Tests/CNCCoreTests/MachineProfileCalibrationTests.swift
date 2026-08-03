import XCTest
@testable import CNCCore

final class MachineProfileCalibrationTests: XCTestCase {
    func testCorrectedStepsPerMmScalesByCommandedOverMeasured() {
        let corrected = MachineProfile.correctedStepsPerMm(
            current: 80,
            commandedMm: 100,
            measuredMm: 95
        )
        XCTAssertEqual(corrected!, 80 * (100.0 / 95.0), accuracy: 0.0001)
    }

    func testCorrectedStepsPerMmWhenMachineOvershoots() {
        // Commanded 100 mm, measured 105 → reduce steps/mm.
        let corrected = MachineProfile.correctedStepsPerMm(
            current: 80,
            commandedMm: 100,
            measuredMm: 105
        )
        XCTAssertEqual(corrected!, 80 * (100.0 / 105.0), accuracy: 0.0001)
    }

    func testCorrectedStepsPerMmRejectsBadInput() {
        XCTAssertNil(MachineProfile.correctedStepsPerMm(current: 80, commandedMm: 100, measuredMm: 0))
        XCTAssertNil(MachineProfile.correctedStepsPerMm(current: 0, commandedMm: 100, measuredMm: 100))
        XCTAssertNil(MachineProfile.correctedStepsPerMm(current: 80, commandedMm: 0, measuredMm: 100))
    }

    func testApplyGRBLSettingsReadsDirectionInvertMask() {
        var profile = MachineProfile.ta4
        profile.applyGRBLSettings(["$3": 3]) // X + Y
        XCTAssertTrue(profile.invertX)
        XCTAssertTrue(profile.invertY)
        XCTAssertFalse(profile.invertZ)
    }
}
