import Foundation
import Combine
import AppKit
import CNCCore

@MainActor
final class AppModel: ObservableObject {
    @Published var ports: [SerialPortInfo] = []
    @Published var selectedPort: String?
    @Published var baudRate: Int = 115_200
    @Published var connectionState: GRBLConnectionState = .disconnected
    @Published var status = GRBLStatus()
    @Published var console: [String] = []
    @Published var machine = MachineProfile.ta4
    @Published var jogStep: Double = 10
    @Published var jobText: String = ""
    @Published var jobName: String = "Untitled"
    @Published var previewJob: PlotJob?
    @Published var streamProgress: Double = 0
    @Published var streamState: StreamerState = .idle
    @Published var lastError: String?

    private let client = GRBLClient()
    private let runner = JobRunner()

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    init() {
        runner.attach(client: client)
        client.onConsole = { [weak self] line in
            Task { @MainActor in
                self?.console.append(line)
                if let self, self.console.count > 400 {
                    self.console.removeFirst(self.console.count - 400)
                }
            }
        }
        client.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
        client.onConnectionChange = { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
            }
        }
        runner.onProgress = { [weak self] progress, state in
            Task { @MainActor in
                self?.streamProgress = progress
                self?.streamState = state
            }
        }
        refreshPorts()
    }

    func refreshPorts() {
        ports = SerialPortEnumerator.listPorts()
        if selectedPort == nil {
            selectedPort = ports.first?.path
        }
    }

    func connect() {
        guard let selectedPort else {
            lastError = "Select a serial port"
            return
        }
        lastError = nil
        connectionState = .connecting
        let path = selectedPort
        let baud = baudRate
        let client = self.client
        Task.detached(priority: .userInitiated) {
            do {
                try client.connect(path: path, baudRate: baud)
                await MainActor.run { self.connectionState = .connected }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.connectionState = .fault(error.localizedDescription)
                }
            }
        }
    }

    func disconnect() {
        client.disconnect()
        connectionState = .disconnected
    }

    func updateJobText(_ text: String) {
        jobText = text
        previewJob = Self.previewFromGCode(text)
        runner.loadGCode(text)
    }

    func sendConsole(_ line: String) {
        do {
            try client.sendLine(line)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func softReset() { try? client.softReset() }
    func unlock() { try? client.unlock() }
    func halt() {
        runner.cancel()
        try? client.halt()
    }
    func requestStatus() { try? client.requestStatus() }

    func probe() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        let client = self.client
        Task.detached(priority: .userInitiated) {
            do {
                let result = try client.probe()
                await MainActor.run {
                    self.machine.applyGRBLSettings(result.settings)
                    if !result.buildInfo.isEmpty {
                        self.machine.buildInfo = result.buildInfo
                    }
                    self.console.append("--- Probe complete ---")
                    if !result.buildInfo.isEmpty { self.console.append(result.buildInfo) }
                    if !result.settingsText.isEmpty { self.console.append(result.settingsText) }
                }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func jog(dx: Double, dy: Double, dz: Double = 0) {
        do {
            try client.jog(dx: dx, dy: dy, dz: dz, feed: machine.jogFeed, machine: machine)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func penUp() { try? client.penUp(machine) }
    func penDown() { try? client.penDown(machine) }

    func loadJob(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                lastError = "Could not read file as UTF-8"
                return
            }
            jobName = url.lastPathComponent
            if url.pathExtension.lowercased() == "svg" {
                let job = try SVGToGCode.plotJob(from: text, profile: machine, fitToWorkspace: true)
                previewJob = job
                jobText = SVGToGCode.gcode(from: job, profile: machine)
            } else {
                jobText = text
                previewJob = Self.previewFromGCode(text)
            }
            runner.loadGCode(jobText)
            streamProgress = 0
            streamState = .idle
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startJob() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        runner.loadGCode(jobText)
        runner.start()
    }

    func pauseJob() { runner.pause() }
    func resumeJob() { runner.resume() }
    func cancelJob() { runner.cancel() }

    private static func previewFromGCode(_ text: String) -> PlotJob {
        var commands: [PlotCommand] = []
        var x = 0.0
        var y = 0.0
        var penDown = false
        for raw in GCodeStreamer.normalize(text) {
            let upper = raw.uppercased()
            if upper.contains("Z") {
                if let z = value(in: upper, key: "Z") {
                    penDown = z <= 0.5
                }
            }
            let nx = value(in: upper, key: "X") ?? x
            let ny = value(in: upper, key: "Y") ?? y
            if nx != x || ny != y {
                let p = PlotPoint(x: nx, y: ny)
                commands.append(penDown ? .line(p) : .move(p))
                x = nx; y = ny
            }
        }
        return PlotJob(commands: commands)
    }

    private static func value(in line: String, key: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"\#(key)([-+0-9.]+)"#) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let r = Range(match.range(at: 1), in: line) else { return nil }
        return Double(line[r])
    }
}
