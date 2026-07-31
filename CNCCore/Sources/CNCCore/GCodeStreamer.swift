import Foundation

public enum StreamerState: Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
    case cancelled
    case fault(String)
}

/// Classic GRBL send-on-`ok` streamer (line buffered).
public final class GCodeStreamer: @unchecked Sendable {
    public private(set) var lines: [String] = []
    public private(set) var index: Int = 0
    public private(set) var state: StreamerState = .idle
    public private(set) var awaitingOk: Bool = false

    /// Lines currently considered in-flight awaiting `ok` (simple protocol: 1).
    private let maxInFlight = 1

    public var progress: Double {
        guard !lines.isEmpty else { return 0 }
        return Double(index) / Double(lines.count)
    }

    public var currentLine: String? {
        guard index < lines.count else { return nil }
        return lines[index]
    }

    public init() {}

    public func load(text: String) {
        lines = Self.normalize(text)
        index = 0
        awaitingOk = false
        state = lines.isEmpty ? .idle : .idle
    }

    public func load(lines input: [String]) {
        lines = input
            .map { Self.sanitizeLine($0) }
            .filter { !$0.isEmpty }
        index = 0
        awaitingOk = false
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
        index = 0
        awaitingOk = false
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
    }

    public func reset() {
        index = 0
        awaitingOk = false
        state = .idle
    }

    /// Returns the next line to send, if the streamer is ready for more data.
    public func nextLineToSend() -> String? {
        guard state == .running else { return nil }
        guard !awaitingOk || maxInFlight > 1 else { return nil }
        guard index < lines.count else {
            if !awaitingOk { state = .completed }
            return nil
        }
        let line = lines[index]
        index += 1
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
            return
        }

        if trimmed == "ok" {
            awaitingOk = false
            if index >= lines.count {
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
}
