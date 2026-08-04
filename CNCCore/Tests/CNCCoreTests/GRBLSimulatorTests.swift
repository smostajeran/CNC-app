import XCTest
@testable import CNCCore

final class GRBLSimulatorTests: XCTestCase {
    func testSoftResetBannerAndIdle() throws {
        let sim = GRBLSimulator()
        try sim.open(path: "/dev/sim", baudRate: 115_200)
        try sim.write(Data([GRBLRealtime.softReset]))
        let out = try readAll(sim)
        XCTAssertTrue(out.contains("Grbl 1.1f"))
        XCTAssertEqual(sim.machineState, "Idle")
    }

    func testStatusReportReflectsStateAndPosition() throws {
        let sim = GRBLSimulator()
        try sim.open(path: "/dev/sim", baudRate: 115_200)
        try sim.write(Data("G0 X10 Y20\n".utf8))
        _ = try readAll(sim) // ok
        try sim.write(Data([GRBLRealtime.status]))
        let report = try readAll(sim)
        XCTAssertTrue(report.contains("<Idle|"))
        XCTAssertTrue(report.contains("MPos:10.000,20.000"))
    }

    func testFeedHoldAndCycleStart() throws {
        let sim = GRBLSimulator()
        try sim.open(path: "/dev/sim", baudRate: 115_200)
        // Force Run via hold path: Idle can enter Hold, then ~ restores Run.
        try sim.write(Data([GRBLRealtime.feedHold]))
        XCTAssertEqual(sim.machineState, "Hold")
        try sim.write(Data([GRBLRealtime.cycleStart]))
        XCTAssertEqual(sim.machineState, "Run")
    }

    func testAlarmBlocksUntilUnlock() throws {
        let sim = GRBLSimulator()
        try sim.open(path: "/dev/sim", baudRate: 115_200)
        sim.injectAlarm()
        _ = try readAll(sim)
        try sim.write(Data("G0 X1\n".utf8))
        XCTAssertTrue(try readAll(sim).contains("error:9"))
        try sim.write(Data("$X\n".utf8))
        XCTAssertTrue(try readAll(sim).contains("ok"))
        XCTAssertEqual(sim.machineState, "Idle")
        try sim.write(Data("G0 X1\n".utf8))
        XCTAssertTrue(try readAll(sim).contains("ok"))
    }

    func testSettingsAndBuildInfo() throws {
        let sim = GRBLSimulator()
        try sim.open(path: "/dev/sim", baudRate: 115_200)
        try sim.write(Data("$I\n".utf8))
        let build = try readAll(sim)
        XCTAssertTrue(build.contains("VER:1.1f"))
        XCTAssertTrue(build.contains("ok"))
        try sim.write(Data("$$\n".utf8))
        let settings = try readAll(sim)
        XCTAssertTrue(settings.contains("$130=390.000"))
        XCTAssertTrue(settings.contains("ok"))
    }

    func testInjectedError() throws {
        let sim = GRBLSimulator()
        try sim.open(path: "/dev/sim", baudRate: 115_200)
        sim.nextErrorCode = 20
        try sim.write(Data("G0 X0\n".utf8))
        XCTAssertEqual(try readAll(sim).trimmingCharacters(in: .whitespacesAndNewlines), "error:20")
    }

    private func readAll(_ sim: GRBLSimulator) throws -> String {
        var chunks: [String] = []
        for _ in 0..<20 {
            let data = try sim.read(maxLength: 4096, timeout: 0)
            if data.isEmpty { break }
            chunks.append(String(data: data, encoding: .utf8) ?? "")
        }
        return chunks.joined()
    }
}
