import XCTest
@testable import CNCCore

final class CommissioningTests: XCTestCase {
    func testOversizeIsRejected() {
        var profile = MachineProfile.ta4
        profile.travelX = 195
        profile.travelY = 285
        XCTAssertTrue(Commissioning.oversizeIsRejected(profile: profile))
    }

    func testBoundaryStaysInsideTravel() {
        var profile = MachineProfile.ta4
        profile.travelX = 195
        profile.travelY = 285
        let gcode = Commissioning.boundaryFrameGCode(profile: profile)
        let report = JobPreflight.assess(
            gcode: gcode,
            profile: profile,
            machineState: "Idle",
            workZeroKnown: true,
            isBusy: false
        )
        XCTAssertTrue(report.okToStart, report.issues.map(\.message).joined(separator: "; "))
    }

    func testProfileRoundTripsHeadAndLimits() {
        var profile = MachineProfile.ta4
        profile.penHeadType = .servo
        profile.penUpAngle = 88
        profile.penDownAngle = 42
        profile.softLimitsEnabled = true
        profile.homingEnabled = true
        profile.commissioningComplete = true
        profile.travelX = MachineProfile.conservativeTravelX
        profile.travelY = MachineProfile.conservativeTravelY
        let data = try! JSONEncoder().encode(profile)
        let decoded = try! JSONDecoder().decode(MachineProfile.self, from: data)
        XCTAssertEqual(decoded.penHeadType, .servo)
        XCTAssertEqual(decoded.penUpAngle, 88, accuracy: 0.001)
        XCTAssertTrue(decoded.softLimitsEnabled)
        XCTAssertTrue(decoded.commissioningComplete)
        XCTAssertEqual(decoded.travelX, 195, accuracy: 0.001)
    }
}
