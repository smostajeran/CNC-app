import Foundation

/// In-memory GRBL 1.1-ish transport for hardware-free tests and demos.
///
/// Responds to `$$` / `$I` / `?` / `$X`, realtime hold/start/reset, and acks
/// ordinary lines with `ok` (or injected `error:`). Pure Foundation — works on Linux.
public final class GRBLSimulator: GRBLTransport {
    public private(set) var isOpen = false
    public private(set) var machineState: String = "Idle"
    public var mpos: SIMD3<Double> = .zero
    public var wpos: SIMD3<Double> = .zero
    public var settings: [String: Double] = [
        "$100": 80,
        "$101": 80,
        "$110": 3000,
        "$111": 3000,
        "$130": 390,
        "$131": 200,
    ]

    /// All bytes written by the client (for assertions).
    public private(set) var written: [Data] = []
    /// Lines received (newline-terminated payloads, without trailing `\n`).
    public private(set) var receivedLines: [String] = []
    /// Realtime bytes received.
    public private(set) var realtimeBytes: [UInt8] = []

    /// When non-nil, the next newline-terminated command replies with `error:N` instead of `ok`.
    public var nextErrorCode: Int?
    /// When true, newline commands leave the machine in Alarm until `$X` or soft-reset.
    public var stickyAlarm = false
    /// When true, subsequent `write` calls throw `SerialPortError.writeFailed`.
    public var failWrites = false

    private var readQueue: [Data] = []
    private var lineBuffer = Data()
    private let lock = NSLock()

    public init() {}

    // MARK: - GRBLTransport

    public func open(path: String, baudRate: Int) throws {
        lock.lock(); defer { lock.unlock() }
        isOpen = true
        machineState = "Idle"
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        isOpen = false
    }

    public func write(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { throw SerialPortError.notOpen }
        if failWrites { throw SerialPortError.writeFailed }
        written.append(data)

        // Realtime bytes may arrive alone or interleaved; process byte-wise.
        for byte in data {
            if isRealtime(byte) {
                handleRealtime(byte)
                continue
            }
            lineBuffer.append(byte)
            if byte == 0x0A {
                let lineData = lineBuffer
                lineBuffer.removeAll(keepingCapacity: true)
                var text = String(data: lineData, encoding: .utf8) ?? ""
                if text.hasSuffix("\n") { text.removeLast() }
                if text.hasSuffix("\r") { text.removeLast() }
                handleLine(text)
            }
        }
    }

    public func read(maxLength: Int, timeout: TimeInterval) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { throw SerialPortError.notOpen }
        guard !readQueue.isEmpty else { return Data() }
        let chunk = readQueue.removeFirst()
        if chunk.count <= maxLength { return chunk }
        let head = chunk.prefix(maxLength)
        let tail = chunk.dropFirst(maxLength)
        readQueue.insert(Data(tail), at: 0)
        return Data(head)
    }

    // MARK: - Test controls

    public func injectAlarm() {
        lock.lock(); defer { lock.unlock() }
        machineState = "Alarm"
        enqueue("ALARM:1\n")
    }

    public func injectLine(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        let payload = line.hasSuffix("\n") ? line : line + "\n"
        enqueue(payload)
    }

    public func resetHistory() {
        lock.lock(); defer { lock.unlock() }
        written.removeAll()
        receivedLines.removeAll()
        realtimeBytes.removeAll()
    }

    // MARK: - Internals

    private func isRealtime(_ byte: UInt8) -> Bool {
        byte == GRBLRealtime.status
            || byte == GRBLRealtime.feedHold
            || byte == GRBLRealtime.cycleStart
            || byte == GRBLRealtime.softReset
    }

    private func handleRealtime(_ byte: UInt8) {
        realtimeBytes.append(byte)
        switch byte {
        case GRBLRealtime.softReset:
            machineState = "Idle"
            stickyAlarm = false
            lineBuffer.removeAll(keepingCapacity: true)
            enqueue("Grbl 1.1f ['$' for help]\n")
        case GRBLRealtime.feedHold:
            if machineState == "Run" || machineState == "Idle" {
                machineState = "Hold"
            }
        case GRBLRealtime.cycleStart:
            if machineState == "Hold" {
                machineState = "Run"
            }
        case GRBLRealtime.status:
            enqueue(statusReport() + "\n")
        default:
            break
        }
    }

    private func handleLine(_ text: String) {
        receivedLines.append(text)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if machineState == "Alarm", !trimmed.hasPrefix("$X"), trimmed != "$X" {
            enqueue("error:9\n") // locked / alarm
            return
        }

        if trimmed == "$I" || trimmed.hasPrefix("$I") {
            enqueue("[VER:1.1f.20190825:].\n")
            enqueue("ok\n")
            return
        }

        if trimmed == "$$" {
            for key in settings.keys.sorted() {
                let value = settings[key] ?? 0
                enqueue(String(format: "%@=%.3f\n", key, value))
            }
            enqueue("ok\n")
            return
        }

        if trimmed == "$X" {
            machineState = "Idle"
            stickyAlarm = false
            enqueue("ok\n")
            return
        }

        if trimmed.hasPrefix("$") && trimmed.contains("=") {
            // Setting write: $100=80.5
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                if let value = Double(parts[1]) {
                    settings[key] = value
                }
            }
            enqueue("ok\n")
            return
        }

        if let code = nextErrorCode {
            nextErrorCode = nil
            enqueue("error:\(code)\n")
            return
        }

        if stickyAlarm {
            machineState = "Alarm"
            enqueue("ok\n")
            return
        }

        // Motion-ish lines briefly look like Run, then Idle (instant planner).
        let upper = trimmed.uppercased()
        if upper.hasPrefix("G0") || upper.hasPrefix("G1") || upper.hasPrefix("G2")
            || upper.hasPrefix("G3") || upper.hasPrefix("$J=") {
            machineState = "Run"
            updatePosition(from: upper)
            machineState = "Idle"
        }

        enqueue("ok\n")
    }

    private func updatePosition(from line: String) {
        func axis(_ name: Character) -> Double? {
            guard let idx = line.firstIndex(of: name) else { return nil }
            let rest = line[line.index(after: idx)...]
            var num = ""
            for ch in rest {
                if ch.isNumber || ch == "." || ch == "-" || ch == "+" {
                    num.append(ch)
                } else if !num.isEmpty {
                    break
                }
            }
            return Double(num)
        }
        if let x = axis("X") { mpos.x = x; wpos.x = x }
        if let y = axis("Y") { mpos.y = y; wpos.y = y }
        if let z = axis("Z") { mpos.z = z; wpos.z = z }
    }

    private func statusReport() -> String {
        String(
            format: "<%@|MPos:%.3f,%.3f,%.3f|WPos:%.3f,%.3f,%.3f|FS:0,0>",
            machineState,
            mpos.x, mpos.y, mpos.z,
            wpos.x, wpos.y, wpos.z
        )
    }

    private func enqueue(_ text: String) {
        readQueue.append(Data(text.utf8))
    }
}
