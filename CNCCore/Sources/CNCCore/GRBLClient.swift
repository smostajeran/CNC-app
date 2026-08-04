import Foundation

public protocol GRBLTransport: AnyObject {
    var isOpen: Bool { get }
    func open(path: String, baudRate: Int) throws
    func close()
    func write(_ data: Data) throws
    func read(maxLength: Int, timeout: TimeInterval) throws -> Data
}

extension SerialPort: GRBLTransport {}

/// High-level GRBL session over a serial transport.
public final class GRBLClient: @unchecked Sendable {
    private let transport: GRBLTransport
    private let queue = DispatchQueue(label: "cnc.grbl.client")
    private var readBuffer = Data()
    private var pollTimer: DispatchSourceTimer?
    private var lineWaiters: [CheckedContinuation<String, Never>] = []

    public private(set) var connectionState: GRBLConnectionState = .disconnected
    public private(set) var lastStatus = GRBLStatus()
    public private(set) var consoleLines: [String] = []
    public var onConsole: ((String) -> Void)?
    public var onStatus: ((GRBLStatus) -> Void)?
    public var onConnectionChange: ((GRBLConnectionState) -> Void)?
    public var onLine: ((String) -> Void)?

    /// Scales connect/probe sleeps. Unit tests set this to `0` for speed.
    public var timingScale: Double = 1.0

    public init(transport: GRBLTransport = SerialPort()) {
        self.transport = transport
    }

    public func connect(path: String, baudRate: Int = 115_200) throws {
        setConnection(.connecting)
        do {
            try transport.open(path: path, baudRate: baudRate)
        } catch {
            setConnection(.fault(error.localizedDescription))
            throw error
        }

        // Nano auto-reset settle
        sleepScaled(2.0)
        try softReset()
        sleepScaled(0.4)
        _ = try drain(timeout: max(0.05, 0.5 * timingScale))
        setConnection(.connected)
        startPolling()
    }

    public func disconnect() {
        stopPolling()
        transport.close()
        setConnection(.disconnected)
    }

    public func sendLine(_ line: String) throws {
        guard transport.isOpen else { throw SerialPortError.notOpen }
        let payload = line.hasSuffix("\n") ? line : line + "\n"
        appendConsole("> \(line)")
        guard let data = payload.data(using: .utf8) else { throw SerialPortError.writeFailed }
        try transport.write(data)
    }

    public func sendRealtime(_ byte: UInt8) throws {
        guard transport.isOpen else { throw SerialPortError.notOpen }
        try transport.write(Data([byte]))
    }

    public func softReset() throws {
        try sendRealtime(GRBLRealtime.softReset)
        appendConsole("> <soft-reset>")
    }

    public func feedHold() throws {
        try sendRealtime(GRBLRealtime.feedHold)
        appendConsole("> !")
    }

    public func cycleStart() throws {
        try sendRealtime(GRBLRealtime.cycleStart)
        appendConsole("> ~")
    }

    public func requestStatus() throws {
        try sendRealtime(GRBLRealtime.status)
    }

    public func unlock() throws {
        try sendLine("$X")
    }

    public func halt() throws {
        try feedHold()
        sleepScaled(0.05)
        try softReset()
    }

    public func jog(dx: Double, dy: Double, dz: Double = 0, feed: Double, machine: MachineProfile) throws {
        let x = machine.invertX ? -dx : dx
        let y = machine.invertY ? -dy : dy
        let z = machine.invertZ ? -dz : dz
        // GRBL 1.1 jogging
        var parts = ["$J=G91 G21"]
        if x != 0 { parts.append("X\(fmt(x))") }
        if y != 0 { parts.append("Y\(fmt(y))") }
        if z != 0 { parts.append("Z\(fmt(z))") }
        parts.append("F\(fmt(feed))")
        try sendLine(parts.joined(separator: " "))
    }

    public func penUp(_ machine: MachineProfile) throws {
        try sendLine("G90 G0 Z\(fmt(machine.penUpZ))")
    }

    public func penDown(_ machine: MachineProfile) throws {
        try sendLine("G90 G1 Z\(fmt(machine.penDownZ)) F\(fmt(machine.drawFeed))")
    }

    /// Set current XY as work coordinate zero (G54 via G10 L20).
    public func setWorkZero() throws {
        try sendLine("G10 L20 P1 X0 Y0")
    }

    /// Pen up, then rapid to work origin.
    public func goToOrigin(machine: MachineProfile) throws {
        try penUp(machine)
        try sendLine("G90 G0 X0 Y0")
    }

    /// Write a GRBL `$` setting (e.g. `$100=80`).
    public func setSetting(_ key: String, value: Double) throws {
        let name = key.hasPrefix("$") ? key : "$\(key)"
        try sendLine("\(name)=\(fmt(value))")
    }

    /// Soft max travel in mm (`$130` / `$131`).
    public func applyTravelLimits(x: Double, y: Double) throws {
        try setSetting("$130", value: x)
        try setSetting("$131", value: y)
    }

    /// Steps per mm (`$100` / `$101`).
    public func applyStepsPerMm(x: Double?, y: Double?) throws {
        if let x { try setSetting("$100", value: x) }
        if let y { try setSetting("$101", value: y) }
    }

    /// Write steps/mm, then read `$$` back and return the confirmed values.
    public func applyStepsPerMmWithReadback(x: Double?, y: Double?) throws -> (x: Double?, y: Double?) {
        stopPolling()
        defer { startPolling() }
        try applyStepsPerMm(x: x, y: y)
        sleepScaled(0.15)
        _ = try drain(timeout: max(0.05, 0.2 * timingScale))
        try sendLine("$$")
        let text = try collectUntilOk(timeout: max(0.2, 3.0 * timingScale))
        let settings = GRBLProbeResult.parseSettings(text)
        return (settings["$100"], settings["$101"])
    }

    /// Brief pen-down mark on paper, then lift (for calibration dots).
    public func markPoint(machine: MachineProfile, dwellSeconds: Double = 0.15) throws {
        try penDown(machine)
        sleepScaled(dwellSeconds)
        try penUp(machine)
    }

    public func probe() throws -> GRBLProbeResult {
        stopPolling()
        defer { startPolling() }

        try softReset()
        sleepScaled(0.5)
        let banner = try drain(timeout: max(0.05, 0.8 * timingScale))

        try sendLine("$I")
        let build = try collectUntilOk(timeout: max(0.2, 2.0 * timingScale))

        try sendLine("$$")
        let settingsText = try collectUntilOk(timeout: max(0.2, 3.0 * timingScale))

        let result = GRBLProbeResult(
            buildInfo: build,
            settingsText: settingsText,
            settings: GRBLProbeResult.parseSettings(settingsText),
            banner: banner
        )
        appendConsole(result.buildInfo)
        appendConsole(result.settingsText)
        return result
    }

    // MARK: - Internals

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func poll() {
        do {
            let chunk = try transport.read(maxLength: 4096, timeout: 0.0)
            guard !chunk.isEmpty else { return }
            readBuffer.append(chunk)
            while let line = popLine() {
                handleIncoming(line)
            }
        } catch {
            setConnection(.fault(error.localizedDescription))
        }
    }

    private func popLine() -> String? {
        guard let idx = readBuffer.firstIndex(of: 0x0A) else { return nil }
        let slice = readBuffer.subdata(in: readBuffer.startIndex..<idx)
        let next = readBuffer.index(after: idx)
        readBuffer.removeSubrange(readBuffer.startIndex..<next)
        var line = String(data: slice, encoding: .utf8) ?? ""
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }

    private func handleIncoming(_ line: String) {
        appendConsole(line)
        onLine?(line)
        if let status = GRBLStatus.parse(line) {
            lastStatus = status
            onStatus?(status)
        }
    }

    private func drain(timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var chunks: [String] = []
        while Date() < deadline {
            let data = try transport.read(maxLength: 4096, timeout: 0.05)
            if !data.isEmpty {
                readBuffer.append(data)
                while let line = popLine() {
                    handleIncoming(line)
                    chunks.append(line)
                }
            }
        }
        return chunks.joined(separator: "\n")
    }

    private func collectUntilOk(timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var lines: [String] = []
        while Date() < deadline {
            let data = try transport.read(maxLength: 4096, timeout: 0.05)
            if !data.isEmpty {
                readBuffer.append(data)
            }
            while let line = popLine() {
                handleIncoming(line)
                if line == "ok" {
                    return lines.joined(separator: "\n")
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func setConnection(_ state: GRBLConnectionState) {
        connectionState = state
        onConnectionChange?(state)
    }

    private func appendConsole(_ line: String) {
        guard !line.isEmpty else { return }
        consoleLines.append(line)
        if consoleLines.count > 500 {
            consoleLines.removeFirst(consoleLines.count - 500)
        }
        onConsole?(line)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private func sleepScaled(_ seconds: TimeInterval) {
        let scaled = seconds * timingScale
        guard scaled > 0 else { return }
        Thread.sleep(forTimeInterval: scaled)
    }
}
