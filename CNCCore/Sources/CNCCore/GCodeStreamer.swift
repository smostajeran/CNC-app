import Foundation

public enum StreamerState: Equatable, Sendable {
    case idle
    case running
    case paused
    case waitingForPenChange
    case completed
    case cancelled
    case fault(String)
}

/// GRBL character-window streamer with host-side M0 pen-change pause.
///
/// All mutable state is guarded by `lock` so UI (main) and `JobRunner`’s serial
/// queue can touch the streamer without racing Array storage.
public final class GCodeStreamer: @unchecked Sendable {
    /// GRBL default serial RX buffer size.
    public static let rxBufferSize = 127

    private let lock = NSLock()

    private var _lines: [String] = []
    private var _index: Int = 0
    private var _ackedCount: Int = 0
    private var _state: StreamerState = .idle
    private var _awaitingOk: Bool = false
    private var _bytesInFlight: Int = 0
    private var _penChangePending: Bool = false
    private var _inFlightCosts: [Int] = []
    private var _inFlightIsPenChange: [Bool] = []
    private var _requireIdleForCompletion: Bool = true
    private var _awaitingIdleForCompletion: Bool = false

    public var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return _lines
    }

    public var index: Int {
        lock.lock(); defer { lock.unlock() }
        return _index
    }

    public var ackedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _ackedCount
    }

    public var state: StreamerState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public var awaitingOk: Bool {
        lock.lock(); defer { lock.unlock() }
        return _awaitingOk
    }

    public var bytesInFlight: Int {
        lock.lock(); defer { lock.unlock() }
        return _bytesInFlight
    }

    public var penChangePending: Bool {
        lock.lock(); defer { lock.unlock() }
        return _penChangePending
    }

    /// When all lines are acked, wait for Idle before `.completed` if requested.
    public var requireIdleForCompletion: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _requireIdleForCompletion }
        set { lock.lock(); defer { lock.unlock() }; _requireIdleForCompletion = newValue }
    }

    public var awaitingIdleForCompletion: Bool {
        lock.lock(); defer { lock.unlock() }
        return _awaitingIdleForCompletion
    }

    /// Progress from acknowledged lines (not merely queued).
    public var progress: Double {
        lock.lock(); defer { lock.unlock() }
        guard !_lines.isEmpty else { return 0 }
        return min(Double(_ackedCount) / Double(_lines.count), 1)
    }

    public var currentLine: String? {
        lock.lock(); defer { lock.unlock() }
        guard _index < _lines.count else { return nil }
        return _lines[_index]
    }

    public var inFlightCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _inFlightCosts.count
    }

    public init() {}

    public func load(text: String) {
        lock.lock(); defer { lock.unlock() }
        _lines = Self.normalize(text)
        resetCountersUnlocked()
        _state = .idle
    }

    public func load(lines input: [String]) {
        lock.lock(); defer { lock.unlock() }
        _lines = input
            .map { Self.sanitizeLine($0) }
            .filter { !$0.isEmpty }
        resetCountersUnlocked()
        _state = .idle
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard !_lines.isEmpty else {
            _state = .completed
            return
        }
        if case .paused = _state {
            _state = .running
            return
        }
        if case .waitingForPenChange = _state {
            return
        }
        resetCountersUnlocked()
        _state = .running
    }

    public func pause() {
        lock.lock(); defer { lock.unlock() }
        if _state == .running { _state = .paused }
    }

    public func resume() {
        lock.lock(); defer { lock.unlock() }
        if _state == .paused {
            _state = .running
            return
        }
        if _state == .waitingForPenChange {
            _penChangePending = false
            _state = .running
        }
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        _state = .cancelled
        _awaitingOk = false
        _penChangePending = false
        _awaitingIdleForCompletion = false
        _inFlightCosts.removeAll()
        _inFlightIsPenChange.removeAll()
        _bytesInFlight = 0
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        resetCountersUnlocked()
        _state = .idle
    }

    /// Notify that GRBL reported Idle (used to finalize completion).
    public func noteMachineIdle() {
        lock.lock(); defer { lock.unlock() }
        guard _awaitingIdleForCompletion else { return }
        _awaitingIdleForCompletion = false
        if _ackedCount >= _lines.count && _inFlightCosts.isEmpty {
            _state = .completed
        }
    }

    /// Returns the next line if it fits in the remaining RX buffer window.
    /// Host-side M0: drains in-flight lines first, sends M0 alone, then waits for Resume.
    public func nextLineToSend() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard _state == .running else { return nil }
        guard _index < _lines.count else {
            maybeFinishSendingUnlocked()
            return nil
        }

        let line = _lines[_index]
        let isPen = GCodeParser.isPenChange(line.uppercased())

        // Never queue motion behind an in-flight or host-paused pen change.
        if _penChangePending || _inFlightIsPenChange.contains(true) { return nil }

        if isPen {
            // Drain planner buffer before sending M0 so motion finishes first.
            guard _inFlightCosts.isEmpty else { return nil }
            _index += 1
            let cost = Self.byteCost(line)
            _bytesInFlight += cost
            _inFlightCosts.append(cost)
            _inFlightIsPenChange.append(true)
            _awaitingOk = true
            return line
        }

        let cost = Self.byteCost(line)
        guard _bytesInFlight + cost <= Self.rxBufferSize else { return nil }

        _index += 1
        _bytesInFlight += cost
        _inFlightCosts.append(cost)
        _inFlightIsPenChange.append(false)
        _awaitingOk = true
        return line
    }

    /// Feed a controller response line (`ok`, `error:N`, status, etc.).
    public func handleResponse(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock(); defer { lock.unlock() }

        if trimmed.hasPrefix("error") || trimmed.hasPrefix("ALARM") {
            _state = .fault(trimmed)
            _awaitingOk = false
            _penChangePending = false
            _awaitingIdleForCompletion = false
            _inFlightCosts.removeAll()
            _inFlightIsPenChange.removeAll()
            _bytesInFlight = 0
            return
        }

        if trimmed == "ok" {
            guard !_inFlightCosts.isEmpty else { return }
            let cost = _inFlightCosts.removeFirst()
            let wasPen = _inFlightIsPenChange.isEmpty ? false : _inFlightIsPenChange.removeFirst()
            _bytesInFlight = max(0, _bytesInFlight - cost)
            _ackedCount += 1
            _awaitingOk = !_inFlightCosts.isEmpty

            if wasPen {
                _penChangePending = true
                _state = .waitingForPenChange
                return
            }

            if _index >= _lines.count && _inFlightCosts.isEmpty {
                maybeFinishSendingUnlocked()
            }
        }
    }

    public static func normalize(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { sanitizeLine(String($0)) }
            .filter { !$0.isEmpty }
    }

    public static func sanitizeLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = s.firstIndex(of: ";") {
            s = String(s[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        if s.hasPrefix("("), s.hasSuffix(")") { return "" }
        return s
    }

    public static func byteCost(_ line: String) -> Int {
        line.utf8.count + 1 // trailing newline
    }

    private func maybeFinishSendingUnlocked() {
        guard _inFlightCosts.isEmpty, _ackedCount >= _lines.count else { return }
        if _requireIdleForCompletion {
            _awaitingIdleForCompletion = true
            // Stay `.running` until Idle; UI can show ~99% until then.
        } else {
            _state = .completed
        }
    }

    private func resetCountersUnlocked() {
        _index = 0
        _ackedCount = 0
        _awaitingOk = false
        _penChangePending = false
        _awaitingIdleForCompletion = false
        _bytesInFlight = 0
        _inFlightCosts.removeAll()
        _inFlightIsPenChange.removeAll()
    }
}
