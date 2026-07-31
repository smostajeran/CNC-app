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
    /// Shown when USB is up but jog does not change position (classic unpowered TA-4).
    @Published var motionWarning: String?
    @Published var confirmFactoryReset = false
    @Published var firmwareAssessment = FirmwareAssessment.assess(buildInfo: "", banner: "")
    @Published var lastProbeBanner: String = ""
    @Published var calibrationNote: String?

    private let client = GRBLClient()
    private let runner = JobRunner()
    private var positionBeforeJog: SIMD3<Double>?
    private var jogCheckTask: Task<Void, Never>?
    private static let profileDefaultsKey = "quill.machineProfile"

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var portsEmpty: Bool { ports.isEmpty }

    var isAlarm: Bool {
        status.state.localizedCaseInsensitiveContains("alarm")
    }

    /// Static checklist when no USB serial ports are listed.
    static let emptyPortHelp = """
    No USB serial port found. Checklist:
    • Use a data USB cable (not charge-only).
    • Plug directly into the Mac (avoid flaky hubs).
    • Install/allow the CH340 (WCH) driver: System Settings → General → Login Items & Extensions → Driver Extensions.
    • Quit other apps that may hold the COM port (Bachin Draw, Candle, serial monitors).
    • Power the machine with its 12V adapter — USB alone can show a port while motors stay dead.
    """

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
                guard let self else { return }
                self.status = status
                if status.state.localizedCaseInsensitiveContains("alarm") {
                    self.motionWarning = "Controller is in Alarm — press Unlock ($X), then Soft Reset if needed."
                }
            }
        }
        client.onConnectionChange = { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
                if case .disconnected = state {
                    self?.motionWarning = nil
                }
            }
        }
        runner.onProgress = { [weak self] progress, state in
            Task { @MainActor in
                self?.streamProgress = progress
                self?.streamState = state
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.profileDefaultsKey),
           let saved = try? JSONDecoder().decode(MachineProfile.self, from: data) {
            machine = saved
        }
        refreshPorts()
    }

    func persistMachine() {
        if let data = try? JSONEncoder().encode(machine) {
            UserDefaults.standard.set(data, forKey: Self.profileDefaultsKey)
        }
    }

    /// Save paper / bed size in Quill and optionally write soft limits to the controller.
    func applyPaperSize(widthMm: Double, heightMm: Double, writeToController: Bool) {
        guard widthMm > 10, heightMm > 10 else {
            lastError = "Paper size must be larger than 10 mm."
            return
        }
        machine.travelX = widthMm
        machine.travelY = heightMm
        persistMachine()
        guard writeToController else {
            calibrationNote = String(format: "Drawing area set to %.0f × %.0f mm in Quill.", widthMm, heightMm)
            return
        }
        guard isConnected else {
            lastError = "Connect first to save size on the machine."
            return
        }
        do {
            try client.applyTravelLimits(x: widthMm, y: heightMm)
            console.append(String(format: "--- Soft limits $130/$131 = %.1f × %.1f ---", widthMm, heightMm))
            calibrationNote = String(
                format: "Drawing area %.0f × %.0f mm saved in Quill and on the machine.",
                widthMm,
                heightMm
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Mark the current pen position as the drawing origin (bottom-left of the paper).
    func setDrawingOriginHere() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        do {
            try client.setWorkOriginZero()
            console.append("--- Work origin set here (G54 X0 Y0) ---")
            calibrationNote = "Start corner set. Drawings will begin from this spot."
            requestStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// After a commanded move, apply a measured length to correct steps/mm on one axis.
    func applyDistanceCalibration(axis: CalibrationAxis, commandedMm: Double, measuredMm: Double) {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        guard measuredMm > 0.1 else {
            lastError = "Enter the length you measured with a ruler (mm)."
            return
        }
        let current: Double
        switch axis {
        case .x:
            current = machine.stepsPerMmX ?? 80
        case .y:
            current = machine.stepsPerMmY ?? 80
        }
        guard let corrected = MachineProfile.correctedStepsPerMm(
            current: current,
            commandedMm: commandedMm,
            measuredMm: measuredMm
        ) else {
            lastError = "Could not calculate a new scale from those numbers."
            return
        }
        do {
            switch axis {
            case .x:
                try client.applyStepsPerMm(x: corrected, y: nil)
                machine.stepsPerMmX = corrected
            case .y:
                try client.applyStepsPerMm(x: nil, y: corrected)
                machine.stepsPerMmY = corrected
            }
            persistMachine()
            console.append(String(format: "--- %@ steps/mm → %.4f (was %.4f) ---", axis.label, corrected, current))
            calibrationNote = String(
                format: "%@ scale updated. Commanded %.0f mm, you measured %.1f mm.",
                axis.label,
                commandedMm,
                measuredMm
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Jog a known distance for the ruler check (pen up first).
    func runCalibrationMove(axis: CalibrationAxis, distanceMm: Double) {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        penUp()
        switch axis {
        case .x: jog(dx: distanceMm, dy: 0)
        case .y: jog(dx: 0, dy: distanceMm)
        }
    }

    func refreshPorts() {
        ports = SerialPortEnumerator.listPorts()
        if selectedPort == nil {
            selectedPort = ports.first?.path
        } else if let selectedPort, !ports.contains(where: { $0.path == selectedPort }) {
            self.selectedPort = ports.first?.path
        }
    }

    func connect() {
        refreshPorts()
        guard !ports.isEmpty else {
            lastError = Self.emptyPortHelp
            return
        }
        guard let selectedPort else {
            lastError = "Select a serial port"
            return
        }
        lastError = nil
        motionWarning = nil
        connectionState = .connecting
        let path = selectedPort
        let baud = baudRate
        let client = self.client
        Task.detached(priority: .userInitiated) {
            do {
                try client.connect(path: path, baudRate: baud)
                await MainActor.run {
                    self.connectionState = .connected
                    self.motionWarning = "USB linked. Confirm the blue power switch / board POWER LED is on (12V). USB can connect with motors unpowered."
                    self.requestStatus()
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.connectionState = .fault(error.localizedDescription)
                }
            }
        }
    }

    func disconnect() {
        jogCheckTask?.cancel()
        client.disconnect()
        connectionState = .disconnected
        motionWarning = nil
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

    func softReset() {
        do {
            try client.softReset()
            motionWarning = nil
            requestStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unlock() {
        do {
            try client.unlock()
            motionWarning = nil
            requestStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestFactoryReset() {
        confirmFactoryReset = true
    }

    func performFactoryReset() {
        confirmFactoryReset = false
        do {
            try client.factoryResetSettings()
            console.append("--- Sent $RST=* (firmware defaults). Soft-reset and Probe to reload. ---")
            softReset()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyInvertToController() {
        do {
            try client.applyDirectionInvert(x: machine.invertX, y: machine.invertY, z: machine.invertZ)
            console.append("--- Applied $3 direction invert from UI toggles ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

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
                    self.persistMachine()
                    self.lastProbeBanner = result.banner
                    self.firmwareAssessment = FirmwareAssessment.assess(
                        buildInfo: result.buildInfo,
                        banner: result.banner,
                        settings: result.settings
                    )
                    self.console.append("--- Probe complete ---")
                    self.console.append("Firmware: \(self.firmwareAssessment.summary)")
                    if !result.buildInfo.isEmpty { self.console.append(result.buildInfo) }
                    if !result.settingsText.isEmpty { self.console.append(result.settingsText) }
                }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func jog(dx: Double, dy: Double, dz: Double = 0) {
        positionBeforeJog = status.mpos
        do {
            try client.jog(dx: dx, dy: dy, dz: dz, feed: machine.jogFeed, machine: machine)
            scheduleMotionCheck()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func penUp() {
        positionBeforeJog = status.mpos
        do {
            try client.penUp(machine)
            scheduleMotionCheck(axisZOnly: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func penDown() {
        positionBeforeJog = status.mpos
        do {
            try client.penDown(machine)
            scheduleMotionCheck(axisZOnly: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func scheduleMotionCheck(axisZOnly: Bool = false) {
        jogCheckTask?.cancel()
        jogCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, isConnected else { return }
            requestStatus()
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, isConnected else { return }
            requestStatus()
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let before = positionBeforeJog else { return }

            if isAlarm {
                motionWarning = "Controller is in Alarm — Unlock ($X), check limits, then Soft Reset."
                return
            }

            let after = status.mpos
            let moved: Bool
            if axisZOnly {
                moved = abs(after.z - before.z) > 0.05
            } else {
                moved = abs(after.x - before.x) > 0.05
                    || abs(after.y - before.y) > 0.05
                    || abs(after.z - before.z) > 0.05
            }

            if !moved {
                motionWarning = """
                USB is connected but position did not change after a move command. \
                Check the 12V adapter and blue power switch / board POWER LED — \
                the TA-4 can talk over USB while motors are unpowered.
                """
            } else {
                if motionWarning?.contains("did not change") == true
                    || motionWarning?.contains("USB linked") == true {
                    motionWarning = nil
                }
            }
        }
    }

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

enum CalibrationAxis: String, CaseIterable, Identifiable {
    case x, y

    var id: String { rawValue }

    var label: String {
        switch self {
        case .x: return "Left–right (X)"
        case .y: return "Front–back (Y)"
        }
    }
}
