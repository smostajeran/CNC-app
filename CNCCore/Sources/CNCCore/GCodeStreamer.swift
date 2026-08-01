import Foundation

public enum StreamerState: Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
    case cancelled
    case fault(String)
}

/// GRBL character-window streamer (classic 127-byte RX planner buffer).
public final class GCodeStreamer: @unchecked Sendable {
    /// GRBL default serial RX buffer size.
    public static let rxBufferSize = 127

    public private(set) var lines: [String] = []
    public private(set) var index: Int = 0
    public private(set) var state: StreamerState = .idle
    public private(set) var awaitingOk: Bool = false
    public private(set) var bytesInFlight: Int = 0

    /// Byte costs (line UTF-8 length + newline) for each in-flight line awaiting `ok`.
    private var inFlightCosts: [Int] = []

    public var progress: Double {
        guard !lines.isEmpty else { return 0 }
        return Double(index) / Double(lines.count)
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
        resetCounters()
        state = .running
    }

    public func pause() {
        if state == .running { state = .paused }
    }

    public func resume() {
        if state == .paused { state = .running }
    }

    public func cancel() {
        state = .cancelled
        awaitingOk = false
        inFlightCosts.removeAll()
        bytesInFlight = 0
    }

    public func reset() {
        resetCounters()
        state = .idle
    }

    /// Returns the next line if it fits in the remaining RX buffer window.
    public func nextLineToSend() -> String? {
        guard state == .running else { return nil }
        guard index < lines.count else {
            if inFlightCosts.isEmpty { state = .completed }
            return nil
        }
        let line = lines[index]
        let cost = Self.byteCost(line)
        guard bytesInFlight + cost <= Self.rxBufferSize else { return nil }

        index += 1
        bytesInFlight += cost
        inFlightCosts.append(cost)
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
            inFlightCosts.removeAll()
            bytesInFlight = 0
            return
        }

        if trimmed == "ok" {
            if !inFlightCosts.isEmpty {
                let cost = inFlightCosts.removeFirst()
                bytesInFlight = max(0, bytesInFlight - cost)
            }
            awaitingOk = !inFlightCosts.isEmpty
            if index >= lines.count && inFlightCosts.isEmpty {
                state = .completed
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

    private func resetCounters() {
        index = 0
        awaitingOk = false
        bytesInFlight = 0
        inFlightCosts.removeAll()
    }
}
