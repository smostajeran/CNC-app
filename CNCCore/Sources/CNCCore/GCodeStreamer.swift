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
public final class GCodeStreamer: @unchecked Sendable {
    /// GRBL default serial RX buffer size.
    public static let rxBufferSize = 127

    public private(set) var lines: [String] = []
    /// Next line index to send.
    public private(set) var index: Int = 0
    /// Lines whose `ok` has been received.
    public private(set) var ackedCount: Int = 0
    public private(set) var state: StreamerState = .idle
    public private(set) var awaitingOk: Bool = false
    public private(set) var bytesInFlight: Int = 0
    /// True after M0 has been sent and acked; cleared on resume.
    public private(set) var penChangePending: Bool = false

    /// Byte costs (line UTF-8 length + newline) for each in-flight line awaiting `ok`.
    private var inFlightCosts: [Int] = []
    /// Whether the next in-flight `ok` completes an M0 pause.
    private var inFlightIsPenChange: [Bool] = []
    /// When all lines are acked, wait for Idle before `.completed` if requested.
    public var requireIdleForCompletion: Bool = true
    public private(set) var awaitingIdleForCompletion: Bool = false

    /// Progress from acknowledged lines (not merely queued).
    public var progress: Double {
        guard !lines.isEmpty else { return 0 }
        return min(Double(ackedCount) / Double(lines.count), 1)
    }

    public var currentLine: String? {
        guard index < lines.count else { return nil }
        return lines[index]
    }

    public var inFlightCount: Int { inFlightCosts.count }

    public init() {}

    public func load(text: String) {
        lines = Self.normalize(text)
        resetCounters()
        state = .idle
    }

    public func load(lines input: [String]) {
        lines = input
            .map { Self.sanitizeLine($0) }
            .filter { !$0.isEmpty }
        resetCounters()
        state = .idle
    }

    public func start() {
        guard !lines.isEmpty else {
            state = .completed
            return
        }
        if case .paused = state {
            state = .running
            return
        }
        if case .waitingForPenChange = state {
            return
        }
        resetCounters()
        state = .running
    }

    public func pause() {
        if state == .running { state = .paused }
    }

    public func resume() {
        if state == .paused {
            state = .running
            return
        }
        if state == .waitingForPenChange {
            penChangePending = false
            state = .running
        }
    }

    public func cancel() {
        state = .cancelled
        awaitingOk = false
        penChangePending = false
        awaitingIdleForCompletion = false
        inFlightCosts.removeAll()
        inFlightIsPenChange.removeAll()
        bytesInFlight = 0
    }

    public func reset() {
        resetCounters()
        state = .idle
    }

    /// Notify that GRBL reported Idle (used to finalize completion).
    public func noteMachineIdle() {
        guard awaitingIdleForCompletion else { return }
        awaitingIdleForCompletion = false
        if ackedCount >= lines.count && inFlightCosts.isEmpty {
            state = .completed
        }
    }

    /// Returns the next line if it fits in the remaining RX buffer window.
    /// Host-side M0: drains in-flight lines first, sends M0 alone, then waits for Resume.
    public func nextLineToSend() -> String? {
        guard state == .running else { return nil }
        guard index < lines.count else {
            maybeFinishSending()
            return nil
        }

        let line = lines[index]
        let isPen = GCodeParser.isPenChange(line.uppercased())

        // Never queue motion behind an in-flight or host-paused pen change.
        if penChangePending || inFlightIsPenChange.contains(true) { return nil }

        if isPen {
            // Drain planner buffer before sending M0 so motion finishes first.
            guard inFlightCosts.isEmpty else { return nil }
            index += 1
            let cost = Self.byteCost(line)
            bytesInFlight += cost
            inFlightCosts.append(cost)
            inFlightIsPenChange.append(true)
            awaitingOk = true
            return line
        }

        let cost = Self.byteCost(line)
        guard bytesInFlight + cost <= Self.rxBufferSize else { return nil }

        index += 1
        bytesInFlight += cost
        inFlightCosts.append(cost)
        inFlightIsPenChange.append(false)
        awaitingOk = true
        return line
    }

    /// Feed a controller response line (`ok`, `error:N`, status, etc.).
    public func handleResponse(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("error") || trimmed.hasPrefix("ALARM") {
            state = .fault(trimmed)
            awaitingOk = false
            penChangePending = false
            awaitingIdleForCompletion = false
            inFlightCosts.removeAll()
            inFlightIsPenChange.removeAll()
            bytesInFlight = 0
            return
        }

        if trimmed == "ok" {
            guard !inFlightCosts.isEmpty else { return }
            let cost = inFlightCosts.removeFirst()
            let wasPen = inFlightIsPenChange.isEmpty ? false : inFlightIsPenChange.removeFirst()
            bytesInFlight = max(0, bytesInFlight - cost)
            ackedCount += 1
            awaitingOk = !inFlightCosts.isEmpty

            if wasPen {
                penChangePending = true
                state = .waitingForPenChange
                return
            }

            if index >= lines.count && inFlightCosts.isEmpty {
                maybeFinishSending()
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

    private func maybeFinishSending() {
        guard inFlightCosts.isEmpty, ackedCount >= lines.count else { return }
        if requireIdleForCompletion {
            awaitingIdleForCompletion = true
            // Stay `.running` until Idle; UI can show ~99% until then.
        } else {
            state = .completed
        }
    }

    private func resetCounters() {
        index = 0
        ackedCount = 0
        awaitingOk = false
        penChangePending = false
        awaitingIdleForCompletion = false
        bytesInFlight = 0
        inFlightCosts.removeAll()
        inFlightIsPenChange.removeAll()
    }
}
