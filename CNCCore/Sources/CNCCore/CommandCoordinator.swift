import Foundation

/// Why the serial port is exclusively owned (manual commands blocked).
public enum MachineBusyReason: Equatable, Sendable {
    case streaming
    case waitingForPenChange
    case probing
    case calibrating
}

public enum CommandCoordinatorError: Error, LocalizedError, Equatable {
    case notConnected
    case busy(MachineBusyReason)
    case notStreaming

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the controller."
        case .busy(let reason):
            switch reason {
            case .streaming:
                return "A job is running — stop or pause it before sending other commands."
            case .waitingForPenChange:
                return "Waiting for pen change — press Resume after swapping the pen."
            case .probing:
                return "Probe in progress — wait until it finishes."
            case .calibrating:
                return "Calibration in progress — finish or close the wizard first."
            }
        case .notStreaming:
            return "No active job stream."
        }
    }
}

/// Exclusive owner of serial line traffic. Realtime bytes (halt / hold / status) always pass.
/// Manual console, jog, probe, and settings writes are blocked while a job owns the port.
public final class CommandCoordinator: @unchecked Sendable {
    private let client: GRBLClient
    private let lock = NSLock()
    private var busy: MachineBusyReason?

    public var onBusyChange: ((MachineBusyReason?) -> Void)?

    public init(client: GRBLClient) {
        self.client = client
    }

    public var busyReason: MachineBusyReason? {
        lock.lock(); defer { lock.unlock() }
        return busy
    }

    public var allowsManualCommands: Bool {
        switch busyReason {
        case nil, .calibrating: return true
        default: return false
        }
    }

    public var isJobActive: Bool {
        switch busyReason {
        case .streaming, .waitingForPenChange: return true
        default: return false
        }
    }

    // MARK: - Ownership

    public func beginStreaming() throws {
        try transition(to: .streaming, allowFrom: [nil])
    }

    public func enterPenChangeWait() throws {
        try transition(to: .waitingForPenChange, allowFrom: [.streaming, .waitingForPenChange])
    }

    public func resumeStreamingAfterPenChange() throws {
        try transition(to: .streaming, allowFrom: [.waitingForPenChange])
    }

    public func endStreaming() {
        lock.lock()
        let previous = busy
        if previous == .streaming || previous == .waitingForPenChange {
            busy = nil
        }
        lock.unlock()
        if previous == .streaming || previous == .waitingForPenChange {
            onBusyChange?(nil)
        }
    }

    public func beginProbing() throws {
        try transition(to: .probing, allowFrom: [nil])
    }

    public func endProbing() {
        clearIf(.probing)
    }

    public func beginCalibrating() throws {
        try transition(to: .calibrating, allowFrom: [nil])
    }

    public func endCalibrating() {
        clearIf(.calibrating)
    }

    // MARK: - Sends

    public func sendManualLine(_ line: String) throws {
        try requireManual()
        try client.sendLine(line)
    }

    public func sendJobLine(_ line: String) throws {
        lock.lock()
        let reason = busy
        lock.unlock()
        guard reason == .streaming else { throw CommandCoordinatorError.notStreaming }
        try client.sendLine(line)
    }

    public func jog(dx: Double, dy: Double, dz: Double = 0, feed: Double, machine: MachineProfile) throws {
        try requireManual()
        try client.jog(dx: dx, dy: dy, dz: dz, feed: feed, machine: machine)
    }

    public func penUp(_ machine: MachineProfile) throws {
        try requireManual()
        try client.penUp(machine)
    }

    public func penDown(_ machine: MachineProfile) throws {
        try requireManual()
        try client.penDown(machine)
    }

    public func markPoint(machine: MachineProfile) throws {
        try requireManual()
        try client.markPoint(machine: machine)
    }

    public func setWorkZero() throws {
        try requireManual()
        try client.setWorkZero()
    }

    public func goToOrigin(machine: MachineProfile) throws {
        try requireManual()
        try client.goToOrigin(machine: machine)
    }

    public func applyStepsPerMm(x: Double?, y: Double?) throws {
        try requireManual()
        try client.applyStepsPerMm(x: x, y: y)
    }

    public func applyStepsPerMmWithReadback(x: Double?, y: Double?) throws -> (x: Double?, y: Double?) {
        try requireManual()
        return try client.applyStepsPerMmWithReadback(x: x, y: y)
    }

    public func applyTravelLimits(x: Double, y: Double) throws {
        try requireManual()
        try client.applyTravelLimits(x: x, y: y)
    }

    public func setSetting(_ key: String, value: Double) throws {
        try requireManual()
        try client.setSetting(key, value: value)
    }

    /// Recovery-only: turn soft limits off so Unlock is not immediately re-tripped.
    public func disableSoftLimitsForRecovery() throws {
        try requireConnected()
        try client.setSetting("$20", value: 0)
    }

    /// Always allowed when connected — recovery must not be blocked by busy state.
    public func softReset() throws {
        try requireConnected()
        try client.softReset()
        clearControllerOwnedBusy()
    }

    /// Always allowed when connected — soft-reset + `$X` to clear Alarm even after E-Stop / probe hang.
    public func unlock() throws {
        try requireConnected()
        try client.unlock()
        clearControllerOwnedBusy()
    }

    /// Home X/Y to the physical end switches via GRBL `$H`.
    public func homeXY(machine: MachineProfile) throws {
        try requireManual()
        try client.homeXY(machine: machine)
    }

    /// Always allowed — emergency / hold / status / unlock recovery.
    public func feedHold() throws { try client.feedHold() }
    public func cycleStart() throws { try client.cycleStart() }
    public func halt() throws {
        try client.halt()
        clearControllerOwnedBusy()
    }
    public func requestStatus() throws { try client.requestStatus() }

    public func probe() throws -> GRBLProbeResult {
        try beginProbing()
        defer { endProbing() }
        return try client.probe()
    }

    /// Settings dump without soft-reset or busy-state change (works while calibrating).
    public func readSettings() throws -> [String: Double] {
        try requireManual()
        return try client.readSettings()
    }

    // MARK: - Internals

    private func requireConnected() throws {
        guard client.connectionState == .connected else {
            throw CommandCoordinatorError.notConnected
        }
    }

    private func requireManual() throws {
        lock.lock()
        let reason = busy
        lock.unlock()
        // Calibrating marks the session busy for job start / probe, but still allows jog & settings.
        if let reason, reason != .calibrating {
            throw CommandCoordinatorError.busy(reason)
        }
        try requireConnected()
    }

    /// After soft-reset / halt / unlock the controller has dropped any in-flight motion.
    /// Clear job/probe ownership so Unlock cannot stay stuck behind a dead busy flag.
    /// Keep `.calibrating` — that is a Quill wizard session, not controller ownership.
    private func clearControllerOwnedBusy() {
        lock.lock()
        let previous = busy
        if previous == .streaming || previous == .waitingForPenChange || previous == .probing {
            busy = nil
        }
        lock.unlock()
        if previous == .streaming || previous == .waitingForPenChange || previous == .probing {
            onBusyChange?(nil)
        }
    }

    private func transition(to next: MachineBusyReason, allowFrom: [MachineBusyReason?]) throws {
        lock.lock()
        let current = busy
        let allowed = allowFrom.contains { $0 == current }
        if allowed {
            busy = next
        }
        lock.unlock()
        guard allowed else {
            if let current {
                throw CommandCoordinatorError.busy(current)
            }
            throw CommandCoordinatorError.busy(.streaming)
        }
        onBusyChange?(next)
    }

    private func clearIf(_ reason: MachineBusyReason) {
        lock.lock()
        let matched = busy == reason
        if matched { busy = nil }
        lock.unlock()
        if matched { onBusyChange?(nil) }
    }
}
