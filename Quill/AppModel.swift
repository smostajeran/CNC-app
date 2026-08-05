import Foundation
import Combine
import AppKit
import CNCCore
import UniformTypeIdentifiers

enum QuillMode: String, CaseIterable {
    case setup, compose, run
}

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
    @Published var jobURL: URL?
    @Published var previewJob: PlotJob?
    @Published var streamProgress: Double = 0
    @Published var streamState: StreamerState = .idle
    @Published var lastError: String?
    @Published var recentJobs: [String] = []
    @Published var watchJobFile: Bool = false
    @Published var textInput: String = "Hello TA-4"
    @Published var textHeightMm: Double = 12
    @Published var penChangeMessage: String?
    @Published var inkDocument = InkDocument()
    @Published var showInkCanvas: Bool = false
    @Published var showCalibrationWizard: Bool = false {
        didSet {
            guard showCalibrationWizard != oldValue else { return }
            if showCalibrationWizard {
                do {
                    try coordinator.beginCalibrating()
                } catch {
                    lastError = error.localizedDescription
                    showCalibrationWizard = false
                }
            } else {
                coordinator.endCalibrating()
            }
        }
    }
    @Published var calibrationNote: String?
    @Published var motionWarning: String?
    /// Title for the top status banner (`motionWarning`).
    @Published var noticeTitle: String = "Check power"
    @Published var confirmFactoryReset = false
    @Published var firmwareAssessment = FirmwareAssessment.assess(buildInfo: "")
    @Published var lastProbeBanner: String = ""
    /// Session flag: user confirmed regulated 12 V + controller POWER LED for calibration.
    @Published var motorsPowerConfirmed = false

    @Published var mode: QuillMode = .setup
    @Published var showDiagnostics = false
    @Published var workZeroKnown = false
    @Published var svgPlacement: SVGPlacementMode = .originalSize
    @Published var svgOffsetX = 0.0
    @Published var svgOffsetY = 0.0
    @Published var preflightReport: JobPreflightReport?
    @Published var busyReason: MachineBusyReason?
    @Published var allowStartDespiteWarnings = false

    // Page & Batch Composer
    @Published var page = PageDocument()
    @Published var selectedElementID: UUID?
    @Published var selectedElementIDs: Set<UUID> = []
    @Published var selectedLayerID: UUID?
    @Published var composedPage: ComposedPage?
    @Published var optimizePaths = true
    @Published var batch = BatchDocument()
    @Published var csvHeaders: [String] = []
    @Published var newTextContent = ""
    @Published var newTextHeight = 10.0
    @Published var projectURL: URL?
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var canvasZoom: Double = 1
    @Published var showTravelPaths = true
    @Published var plotOnlySelectedLayer = false
    @Published var pendingAutosaveRecovery: QuillProject?
    @Published var showAutosaveRecoveryAlert = false

    private let client = GRBLClient()
    private let coordinator: CommandCoordinator
    private let runner = JobRunner()
    private var previewTask: Task<Void, Never>?
    private var statusTimer: Timer?
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileWatchFD: Int32 = -1
    private let documentHistory = DocumentHistory()
    private var clipboardElements: [PageElement] = []
    private var autosaveTimer: Timer?
    private var suppressHistory = false

    private static let recentKey = "quill.recentJobs"
    private static let portKey = "quill.lastPort"
    private static let baudKey = "quill.lastBaud"
    private static let recentProjectsKey = "quill.recentProjects"
    private static let autosaveName = "QuillAutosave.quill"
    private static let lastProjectPathKey = "quill.lastProjectPath"

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var allowsManualCommands: Bool { coordinator.allowsManualCommands }

    var portsEmpty: Bool { ports.isEmpty }

    var isAlarm: Bool {
        status.state.localizedCaseInsensitiveContains("alarm")
    }

    static let emptyPortHelp = """
    No USB serial port found. Checklist:
    • Use a data USB cable (not charge-only).
    • Plug directly into the Mac (avoid flaky hubs).
    • Install/allow the CH340 (WCH) driver: System Settings → General → Login Items & Extensions → Driver Extensions.
    • Quit other apps that may hold the COM port (Bachin Draw, Candle, serial monitors).
    • Power the machine with its 12V adapter — USB can connect with motors unpowered.
    """

    /// True when Start should be blocked by an exclusive owner (not calibration wizard).
    private var isBusyBlockingJob: Bool {
        switch coordinator.busyReason {
        case .streaming, .waitingForPenChange, .probing: return true
        case .calibrating, .none: return false
        }
    }

    init() {
        coordinator = CommandCoordinator(client: client)

        if let saved = MachineProfile.loadFromDefaults() {
            machine = saved
        }
        recentJobs = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        selectedPort = UserDefaults.standard.string(forKey: Self.portKey)
        let baud = UserDefaults.standard.integer(forKey: Self.baudKey)
        if baud > 0 { baudRate = baud }
        selectedLayerID = page.defaultLayerID
        recoverAutosaveIfNeeded()
        startAutosave()

        runner.attach(coordinator: coordinator, client: client)
        coordinator.onBusyChange = { [weak self] reason in
            Task { @MainActor in
                self?.busyReason = reason
            }
        }
        client.onConsole = { [weak self] line in
            Task { @MainActor in
                self?.console.append(line)
                if let self, self.console.count > 400 {
                    self.console.removeFirst(self.console.count - 400)
                }
                if line.contains("PEN CHANGE") || line.hasPrefix("M0") {
                    self?.penChangeMessage = "Pen change pause — swap pen, then Resume"
                }
            }
        }
        client.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.status = status
                self?.runner.noteStatus(status)
                if status.state.localizedCaseInsensitiveContains("alarm") {
                    self?.noticeTitle = "Machine locked"
                    self?.motionWarning = "Controller is in Alarm — tap Unlock in the header, then Soft reset in Advanced if needed."
                }
            }
        }
        client.onConnectionChange = { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
                self?.updateStatusPolling()
            }
        }
        runner.onProgress = { [weak self] progress, state in
            Task { @MainActor in
                self?.streamProgress = progress
                self?.streamState = state
                if state == .running {
                    self?.penChangeMessage = nil
                }
                if state == .completed {
                    self?.markCurrentBatchPageCompleted()
                }
            }
        }
        runner.onPenChange = { [weak self] in
            Task { @MainActor in
                self?.penChangeMessage = "Pen change pause — swap pen, then Resume"
            }
        }
        refreshPorts()
    }

    func persistMachine() {
        machine.clampPressureRange()
        machine.saveToDefaults()
    }

    func refreshPorts() {
        ports = SerialPortEnumerator.listPorts()
        if let selectedPort, ports.contains(where: { $0.path == selectedPort }) {
            return
        }
        selectedPort = ports.first?.path
    }

    func connect() {
        refreshPorts()
        if ports.isEmpty {
            lastError = Self.emptyPortHelp
            return
        }
        guard let selectedPort else {
            lastError = "Select a serial port"
            return
        }
        lastError = nil
        motionWarning = nil
        noticeTitle = "Check power"
        connectionState = .connecting
        UserDefaults.standard.set(selectedPort, forKey: Self.portKey)
        UserDefaults.standard.set(baudRate, forKey: Self.baudKey)
        let path = selectedPort
        let baud = baudRate
        let client = self.client
        Task.detached(priority: .userInitiated) {
            do {
                try client.connect(path: path, baudRate: baud)
                await MainActor.run {
                    self.connectionState = .connected
                    self.noticeTitle = "Check power"
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
        switch streamState {
        case .running, .paused, .waitingForPenChange:
            runner.cancel()
        default:
            break
        }
        coordinator.endStreaming()
        client.disconnect()
        connectionState = .disconnected
        motorsPowerConfirmed = false
        updateStatusPolling()
    }

    /// Calibration and homing must not run on USB-only “connected” without motor power.
    var canCalibrateMotion: Bool {
        isConnected && motorsPowerConfirmed && !isAlarm
    }

    func confirmMotorsPowered(_ confirmed: Bool = true) {
        motorsPowerConfirmed = confirmed
        if confirmed {
            motionWarning = nil
        }
    }

    func updateJobText(_ text: String) {
        jobText = text
        schedulePreviewRebuild()
        // Streamer loads on Start / file open — not every keystroke.
    }

    private func schedulePreviewRebuild() {
        previewTask?.cancel()
        let text = jobText
        let feed = machine.drawFeed
        let rapid = machine.jogFeed
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let job = GCodeParser.parse(text, defaultFeed: feed, defaultRapid: rapid).plotJob.simplified()
            await MainActor.run {
                self?.previewJob = job
            }
        }
    }

    func sendConsole(_ line: String) {
        do {
            try coordinator.sendManualLine(line)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func softReset() { try? coordinator.softReset() }
    func unlock() { try? coordinator.unlock() }

    /// Emergency stop: cancel any job, feed-hold, then soft-reset the controller.
    func halt() {
        penChangeMessage = nil
        runner.cancel()
        try? coordinator.halt()
        noticeTitle = "Emergency stop"
        motionWarning = "Motion halted and the controller was reset. If the header shows Locked, tap Unlock before moving again. Soft reset in Advanced if Unlock alone does not clear it."
        console.append("--- Emergency stop (feed hold + soft reset) ---")
    }
    func feedHold() { try? coordinator.feedHold() }
    func requestStatus() { try? coordinator.requestStatus() }

    func setWorkZero() {
        do {
            try coordinator.setWorkZero()
            workZeroKnown = true
            console.append("--- Work zero set (G10 L20 P1 X0 Y0) ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Hobbyist Calibrate wording — same as Set Zero.
    func setDrawingOriginHere() {
        setWorkZero()
        if lastError == nil {
            calibrationNote = "Start corner set. Drawings will begin from this spot."
        }
    }

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
            try coordinator.applyTravelLimits(x: widthMm, y: heightMm)
            console.append(String(format: "--- Soft limits $130/$131 = %.1f × %.1f ---", widthMm, heightMm))
            calibrationNote = String(
                format: "Drawing area %.0f × %.0f mm saved in Quill and on the machine.",
                widthMm, heightMm
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyInvertToController() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        do {
            try coordinator.setSetting("$3", value: Double(machine.directionInvertMask))
            persistMachine()
            console.append("--- Direction invert $3=\(machine.directionInvertMask) ---")
            calibrationNote = "Axis flips saved to the controller."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestFactoryReset() {
        confirmFactoryReset = true
    }

    func performFactoryReset() {
        confirmFactoryReset = false
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        do {
            try coordinator.sendManualLine("$RST=*")
            console.append("--- Sent $RST=* (firmware defaults). Soft-reset and Probe to reload. ---")
            softReset()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func goToOrigin() {
        do {
            try coordinator.goToOrigin(machine: machine)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Drive X and Y to the physical end switches (GRBL `$H`).
    /// Clear paper clips / obstacles first — the gantry will move until both switches click.
    /// Does not home Z (T-A4 has no Z end stop).
    func homeXY() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        guard motorsPowerConfirmed else {
            lastError = "Confirm 12 V power and the POWER LED before homing. USB can show Connected while motors are unpowered — missed steps make calibration useless."
            return
        }
        guard allowsManualCommands else {
            lastError = "Stop or finish the current job before homing."
            return
        }
        do {
            try coordinator.homeXY(machine: machine)
            console.append("--- Homing X/Y only (pen raised; Z is not homed) — wait until motion stops ---")
            calibrationNote = "Homing X/Y. Wait until the gantry stops at the switches, then continues."
        } catch {
            lastError = error.localizedDescription
                + " If homing is disabled on the controller, enable it ($22=1) or home manually with jog."
        }
    }

    /// Enable GRBL homing (`$22=1`) before the homing test. Soft limits stay off until travel is measured.
    func enableHomingSetting() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        do {
            try coordinator.setSetting("$22", value: 1)
            machine.homingEnabled = true
            persistMachine()
            console.append("--- Homing enabled $22=1 ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Write GRBL `$23` homing-direction invert mask (independent of jog `$3`).
    func applyHomingDirectionToController() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        do {
            try coordinator.setSetting("$23", value: Double(machine.homingDirInvertMask))
            persistMachine()
            console.append("--- Homing direction $23=\(machine.homingDirInvertMask) ---")
            calibrationNote = "Homing seek direction updated ($23). Home again only after the head is clear of the open end."
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Flip which way `$H` seeks on one axis. Use when Home runs away from the end switch.
    func flipHomingDirection(_ axis: CalibrationAxis) {
        switch axis {
        case .x: machine.toggleHomingDirInvert(axisBit: 0)
        case .y: machine.toggleHomingDirInvert(axisBit: 1)
        }
        applyHomingDirectionToController()
    }

    /// Write measured safe travel and enable soft limits (`$20`). Optionally hard limits (`$21`).
    /// Call only after homing works — soft limits need a valid machine position.
    func applySafeTravelAndLimits(
        travelX: Double,
        travelY: Double,
        enableSoftLimits: Bool = true,
        enableHardLimits: Bool = false
    ) {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        guard travelX > 10, travelY > 10 else {
            lastError = "Safe travel must be larger than 10 mm."
            return
        }
        do {
            try coordinator.applyTravelLimits(x: travelX, y: travelY)
            machine.travelX = travelX
            machine.travelY = travelY
            if enableSoftLimits {
                try coordinator.setSetting("$20", value: 1)
                machine.softLimitsEnabled = true
            }
            if enableHardLimits {
                try coordinator.setSetting("$21", value: 1)
                machine.hardLimitsEnabled = true
            } else {
                try coordinator.setSetting("$21", value: 0)
                machine.hardLimitsEnabled = false
            }
            persistMachine()
            console.append(String(
                format: "--- Safe travel $130=%.1f $131=%.1f · $20=%d $21=%d ---",
                travelX, travelY,
                enableSoftLimits ? 1 : 0,
                enableHardLimits ? 1 : 0
            ))
            calibrationNote = String(
                format: "Safe travel %.0f × %.0f mm saved. Soft limits %@. Home again after every power cycle.",
                travelX, travelY,
                enableSoftLimits ? "on" : "off"
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func flipAxisInvert(_ axis: CalibrationAxis) {
        switch axis {
        case .x: machine.invertX.toggle()
        case .y: machine.invertY.toggle()
        }
        persistMachine()
        applyInvertToController()
    }

    /// Raised-pen boundary frame + oversize preflight check (must reject before streaming).
    func runCommissioningSafetyTests() -> (boundaryGCode: String, oversizeRejected: Bool) {
        let boundary = Commissioning.boundaryFrameGCode(profile: machine)
        let rejected = Commissioning.oversizeIsRejected(profile: machine)
        console.append("--- Boundary frame prepared (pen up) ---")
        console.append(rejected
            ? "--- Oversize test correctly rejected by preflight ---"
            : "--- Oversize test FAILED — preflight did not reject ---")
        return (boundary, rejected)
    }

    func finishCommissioningProfile() {
        machine.commissioningComplete = true
        persistMachine()
        calibrationNote = "Machine profile saved (head type, travel, direction, steps/mm, limits, pen heights, firmware)."
        console.append("--- Commissioning complete — profile persisted ---")
    }

    func probe() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        let coordinator = self.coordinator
        Task.detached(priority: .userInitiated) {
            do {
                let result = try coordinator.probe()
                await MainActor.run {
                    self.machine.applyGRBLSettings(result.settings)
                    if !result.buildInfo.isEmpty {
                        self.machine.buildInfo = result.buildInfo
                    }
                    self.lastProbeBanner = result.banner
                    self.firmwareAssessment = FirmwareAssessment.assess(
                        buildInfo: result.buildInfo,
                        banner: result.banner,
                        settings: result.settings
                    )
                    self.persistMachine()
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
        do {
            try coordinator.jog(dx: dx, dy: dy, dz: dz, feed: machine.jogFeed, machine: machine)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func penUp() { try? coordinator.penUp(machine) }
    func penDown() { try? coordinator.penDown(machine) }

    /// Bachin motor-pen manuals document Z heights in 0…8 mm.
    func clampPenHeightsToBachinRange() {
        machine.penUpZ = min(max(machine.penUpZ, 0), 8)
        machine.penDownZ = min(max(machine.penDownZ, 0), 8)
        // Keep up strictly above down for GRBL Z-up (higher lifts the pen).
        if machine.penUpZ <= machine.penDownZ {
            machine.penUpZ = min(machine.penDownZ + 1, 8)
        }
        machine.clampPressureRange()
        persistMachine()
    }

    /// Defaults matching Bachin “pen up gap ≤ 5 mm” guidance (Quill GRBL: up 5, down 0).
    func applyRecommendedPenHeights() {
        machine.penUpZ = 5
        machine.penDownZ = 0
        machine.clampPressureRange()
        persistMachine()
        calibrationNote = "Pen heights set to up 5 mm · down 0 mm. Check the tip clears paper when raised, then touches lightly when down."
    }

    // MARK: - Axis scale calibration wizard

    func setCalibrationWizardOpen(_ open: Bool) {
        showCalibrationWizard = open
    }

    /// Dot the paper at the current XY (pen down briefly).
    func markCalibrationPoint() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        do {
            try coordinator.markPoint(machine: machine)
            console.append("--- Calibration mark ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pen up, then jog a known distance along one axis for the ruler check.
    func runCalibrationMove(axis: CalibrationAxis, distanceMm: Double) {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        guard distanceMm >= 1 else {
            lastError = "Choose a move of at least 1 mm."
            return
        }
        // Prefer work coordinates after Set Zero; otherwise machine position.
        let pos = workZeroKnown ? status.wpos : status.mpos
        let remaining: Double
        switch axis {
        case .x: remaining = machine.travelX - pos.x
        case .y: remaining = machine.travelY - pos.y
        }
        if distanceMm > remaining - 1 {
            lastError = String(
                format: "Move %.1f mm would leave less than 1 mm of travel (%.1f mm remaining on %@).",
                distanceMm, max(0, remaining), axis.shortLabel
            )
            return
        }
        do {
            try coordinator.penUp(machine)
            switch axis {
            case .x:
                try coordinator.jog(dx: distanceMm, dy: 0, feed: machine.jogFeed, machine: machine)
            case .y:
                try coordinator.jog(dx: 0, dy: distanceMm, feed: machine.jogFeed, machine: machine)
            }
            console.append(String(format: "--- Calibration move %@ %.1f mm ---", axis.shortLabel, distanceMm))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// After marking two points and measuring, correct GRBL steps/mm so commanded mm ≈ real mm.
    func applyDistanceCalibration(axis: CalibrationAxis, commandedMm: Double, measuredMm: Double) {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        guard measuredMm > 0.1 else {
            lastError = "Enter the length you measured with a ruler (mm)."
            return
        }
        let current: Double?
        switch axis {
        case .x: current = machine.stepsPerMmX
        case .y: current = machine.stepsPerMmY
        }
        guard let current else {
            lastError = "Probe $$/$I first so Quill knows current steps/mm."
            return
        }
        guard let corrected = MachineProfile.correctedStepsPerMm(
            current: current,
            commandedMm: commandedMm,
            measuredMm: measuredMm
        ) else {
            lastError = "Could not calculate a new scale from those numbers."
            return
        }
        let old = current
        do {
            let readback: Double?
            switch axis {
            case .x:
                let result = try coordinator.applyStepsPerMmWithReadback(x: corrected, y: nil)
                readback = result.x
            case .y:
                let result = try coordinator.applyStepsPerMmWithReadback(x: nil, y: corrected)
                readback = result.y
            }
            guard let readback, abs(readback - corrected) <= 0.05 else {
                switch axis {
                case .x: try? coordinator.applyStepsPerMm(x: old, y: nil)
                case .y: try? coordinator.applyStepsPerMm(x: nil, y: old)
                }
                lastError = String(
                    format: "Steps/mm write failed verification (wanted %.4f, read %@). Rolled back to %.4f.",
                    corrected,
                    readback.map { String(format: "%.4f", $0) } ?? "nil",
                    old
                )
                return
            }
            switch axis {
            case .x: machine.stepsPerMmX = readback
            case .y: machine.stepsPerMmY = readback
            }
            persistMachine()
            console.append(String(
                format: "--- %@ steps/mm → %.4f (was %.4f, readback %.4f) ---",
                axis.shortLabel, corrected, old, readback
            ))
            calibrationNote = String(
                format: "%@ calibrated: commanded %.0f mm, measured %.1f mm → steps/mm %.3f (readback %.3f).",
                axis.label, commandedMm, measuredMm, corrected, readback
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadJob(url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            if ext == "ta4ink" || (ext == "json" && url.lastPathComponent.contains("ink")) {
                loadInkDocument(url: url)
                return
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                lastError = "Could not read file as UTF-8"
                return
            }
            // Heuristic: JSON ink documents
            if text.contains("\"strokes\"") && text.contains("\"pressure\"") {
                inkDocument = try InkDocument.load(from: data)
                showInkCanvas = true
                applyInkToJob()
                rememberRecent(url)
                return
            }
            jobName = url.lastPathComponent
            jobURL = url
            rememberRecent(url)
            applyJobText(text, isSVG: ext == "svg")
            startFileWatchIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadJob(text: String, name: String, isSVG: Bool) {
        jobName = name
        jobURL = nil
        stopFileWatch()
        applyJobText(text, isSVG: isSVG)
    }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let types = pb.types, types.contains(.init("public.svg-image")) || types.contains(.html),
           let str = pb.string(forType: .string) ?? pb.string(forType: .html),
           str.contains("<svg") {
            loadJob(text: str, name: "Clipboard.svg", isSVG: true)
            return
        }
        if let str = pb.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("<svg") {
                loadJob(text: trimmed, name: "Clipboard.svg", isSVG: true)
            } else {
                loadJob(text: trimmed, name: "Clipboard.gcode", isSVG: false)
            }
        }
    }

    func exportInkscapeTemplate() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TA4-workspace.svg"
        panel.allowedContentTypes = [.svg]
        if panel.runModal() == .OK, let url = panel.url {
            let svg = InkscapeTemplate.workspaceSVG(profile: machine)
            do {
                try svg.write(to: url, atomically: true, encoding: .utf8)
                console.append("--- Exported Inkscape template: \(url.lastPathComponent) ---")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func generateTextJob() {
        let gcode = SingleLineText.gcode(
            text: textInput,
            profile: machine,
            heightMm: textHeightMm,
            origin: PlotPoint(x: 10, y: machine.travelY * 0.5)
        )
        loadJob(text: gcode, name: "Text.gcode", isSVG: false)
    }

    // MARK: - Page & Batch Composer

    var currentProject: QuillProject {
        QuillProject(page: page, batch: batch)
    }

    /// Hard plot blocker — never bypassed by “allow warnings”.
    var hasBlockingTextOverflow: Bool {
        if let composed = composedPage, composed.hasBlockingOverflow { return true }
        return page.hasTextOverflow()
    }

    /// Page format must fit the machine bed (e.g. A4 portrait on a 200 mm bed is invalid).
    var pageFitsBed: Bool {
        page.format.fits(on: machine)
    }

    var pageFitBlockingMessage: String? {
        guard !pageFitsBed else { return nil }
        return String(
            format: "“%@” (%.0f×%.0f mm) does not fit the %.0f×%.0f mm bed.",
            page.format.name,
            page.format.widthMm,
            page.format.heightMm,
            machine.travelX,
            machine.travelY
        )
    }

    var suggestedLandscapeFormat: PageFormat? {
        guard !pageFitsBed else { return nil }
        let candidates = PageFormat.presets.filter { $0.fits(on: machine) }
        // Prefer same-family landscape when it fits; otherwise first bed-safe preset.
        let base = page.format.id
            .replacingOccurrences(of: "-portrait", with: "")
            .replacingOccurrences(of: "-landscape", with: "")
        if let match = candidates.first(where: { $0.id == base + "-landscape" }) {
            return match
        }
        if let a5 = candidates.first(where: { $0.id == "a5-landscape" }) {
            return a5
        }
        return candidates.first
    }

    var canPreflightRun: Bool {
        composedPage != nil && !hasBlockingTextOverflow && pageFitsBed
    }

    func beginEditTransaction() {
        guard !suppressHistory else { return }
        _ = documentHistory.beginTransaction(currentProject)
        refreshHistoryFlags()
    }

    func endEditTransaction() {
        documentHistory.endTransaction()
        textEditCheckpointTaken = false
        geometryCheckpointTaken = false
        refreshHistoryFlags()
    }

    /// Single-shot undo checkpoint (add/delete/one-shot actions).
    func checkpointDocument() {
        guard !suppressHistory else { return }
        if documentHistory.isTransactionOpen {
            // Already coalescing; do not push another entry.
            return
        }
        documentHistory.checkpoint(currentProject)
        refreshHistoryFlags()
    }

    func undoDocument() {
        endEditTransaction()
        guard let previous = documentHistory.undo(current: currentProject) else { return }
        applyProject(previous, recordHistory: false)
    }

    func redoDocument() {
        endEditTransaction()
        guard let next = documentHistory.redo(current: currentProject) else { return }
        applyProject(next, recordHistory: false)
    }

    private func refreshHistoryFlags() {
        canUndo = documentHistory.canUndo
        canRedo = documentHistory.canRedo
    }

    private func applyProject(_ project: QuillProject, recordHistory: Bool) {
        suppressHistory = true
        var next = project
        next.page.migrateLegacyText()
        next.page.applyTextBoxSizing()
        page = next.page
        batch = next.batch
        selectedLayerID = page.defaultLayerID
        if let id = selectedElementID, !page.elements.contains(where: { $0.id == id }) {
            selectedElementID = nil
            selectedElementIDs = []
        }
        suppressHistory = false
        if recordHistory { checkpointDocument() }
        refreshHistoryFlags()
        recomposePage()
    }

    func setPageFormat(_ format: PageFormat) {
        beginEditTransaction()
        page.format = format
        // Keep page on bed if possible.
        page.bedOriginX = min(page.bedOriginX, max(0, machine.travelX - format.widthMm))
        page.bedOriginY = min(page.bedOriginY, max(0, machine.travelY - format.heightMm))
        endEditTransaction()
        recomposePage()
    }

    func updatePageSetting(_ mutate: (inout PageDocument) -> Void) {
        beginEditTransaction()
        mutate(&page)
        endEditTransaction()
        recomposePage()
    }

    func updateLayer(_ id: UUID, coalesce: Bool = false, _ mutate: (inout PageLayer) -> Void) {
        guard let idx = page.layers.firstIndex(where: { $0.id == id }) else { return }
        if coalesce {
            beginEditTransaction()
        } else {
            checkpointDocument()
        }
        mutate(&page.layers[idx])
        if !coalesce {
            // one-shot already checkpointed
        }
        recomposePage()
    }

    func endLayerSliderEdit() {
        endEditTransaction()
    }

    func selectElement(_ id: UUID?, additive: Bool = false) {
        guard let id else {
            selectedElementID = nil
            selectedElementIDs = []
            return
        }
        if additive {
            if selectedElementIDs.contains(id) {
                selectedElementIDs.remove(id)
            } else {
                selectedElementIDs.insert(id)
            }
            selectedElementID = selectedElementIDs.first
        } else {
            selectedElementID = id
            selectedElementIDs = [id]
        }
    }

    /// Prevents re-entrant double insertion if ⌘↩ is delivered more than once.
    private var isAddingTextElement = false

    func addTextElement() {
        guard !isAddingTextElement else { return }
        let content = newTextContent
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Enter paragraph text before adding"
            return
        }
        isAddingTextElement = true
        defer { isAddingTextElement = false }

        checkpointDocument()
        let layerID = selectedLayerID ?? page.defaultLayerID
        var style = TextBoxStyle(fontSizeMm: newTextHeight, heightMode: .automatic)
        style.overflowPolicy = .showOverflow
        let el = PageElement(
            name: String(content.prefix(40).replacingOccurrences(of: "\n", with: " ")),
            kind: .textBox(text: content, style: style),
            xMm: 15,
            yMm: page.format.heightMm * 0.45,
            widthMm: min(140, page.format.widthMm - 20),
            heightMm: max(newTextHeight * 4, 36),
            anchor: .bottomLeft,
            layerID: layerID,
            zOrder: (page.elements.map(\.zOrder).max() ?? 0) + 1
        )
        page.elements.append(el)
        page.applyTextBoxSizing()
        selectElement(el.id)
        newTextContent = ""
        recomposePage()
    }

    func addShape(_ kind: PageElement.ShapeKind) {
        checkpointDocument()
        let layerID = selectedLayerID ?? page.defaultLayerID
        let el = PageElement(
            name: kind.rawValue.capitalized,
            kind: .shape(kind),
            xMm: 20,
            yMm: 20,
            widthMm: 40,
            heightMm: kind == .line ? 2 : 30,
            layerID: layerID,
            zOrder: (page.elements.map(\.zOrder).max() ?? 0) + 1
        )
        page.elements.append(el)
        selectElement(el.id)
        recomposePage()
    }

    func addSVGToPage(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            checkpointDocument()
            let layerID = selectedLayerID ?? page.defaultLayerID
            let el = PageElement(
                name: url.lastPathComponent,
                kind: .svg(text),
                xMm: 10,
                yMm: 10,
                widthMm: 80,
                heightMm: 60,
                layerID: layerID,
                zOrder: (page.elements.map(\.zOrder).max() ?? 0) + 1
            )
            page.elements.append(el)
            selectElement(el.id)
            recomposePage()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addInkToPage() {
        guard !inkDocument.strokes.isEmpty else {
            lastError = "Draw handwriting first"
            return
        }
        let samples = inkDocument.strokes.flatMap(\.samples)
        guard let minX = samples.map(\.x).min(),
              let minY = samples.map(\.y).min(),
              let maxX = samples.map(\.x).max(),
              let maxY = samples.map(\.y).max() else {
            lastError = "Draw handwriting first"
            return
        }
        checkpointDocument()
        // Convert machine-space ink into paper-local geometry so compose/transform
        // does not double-apply bed coordinates (which looked like a 90° flip).
        var localInk = inkDocument
        localInk.strokes = inkDocument.strokes.map { stroke in
            InkDocument.Stroke(samples: stroke.samples.map { sample in
                InkDocument.Sample(
                    x: sample.x - minX,
                    y: sample.y - minY,
                    pressure: sample.pressure
                )
            })
        }
        let paperOrigin = page.bedToPaper(x: minX, y: minY)
        let layerID = selectedLayerID ?? page.defaultLayerID
        let el = PageElement(
            name: "Handwriting",
            kind: .ink(localInk),
            xMm: max(0, paperOrigin.x),
            yMm: max(0, paperOrigin.y),
            widthMm: max(maxX - minX, 1),
            heightMm: max(maxY - minY, 1),
            anchor: .bottomLeft,
            layerID: layerID,
            zOrder: (page.elements.map(\.zOrder).max() ?? 0) + 1
        )
        page.elements.append(el)
        selectElement(el.id)
        recomposePage()
    }

    func duplicateSelectedElement() {
        let ids = selectedElementIDs.isEmpty ? Set([selectedElementID].compactMap { $0 }) : selectedElementIDs
        guard !ids.isEmpty else { return }
        checkpointDocument()
        for id in ids { page.duplicateElement(id) }
        recomposePage()
    }

    func deleteSelectedElement() {
        let ids = selectedElementIDs.isEmpty ? Set([selectedElementID].compactMap { $0 }) : selectedElementIDs
        guard !ids.isEmpty else { return }
        checkpointDocument()
        page.elements.removeAll { ids.contains($0.id) }
        selectedElementID = nil
        selectedElementIDs = []
        recomposePage()
    }

    func copySelectedElements() {
        let ids = selectedElementIDs.isEmpty ? Set([selectedElementID].compactMap { $0 }) : selectedElementIDs
        clipboardElements = page.elements.filter { ids.contains($0.id) }
    }

    func pasteClipboardElements() {
        guard !clipboardElements.isEmpty else { return }
        checkpointDocument()
        var newIDs: Set<UUID> = []
        for el in clipboardElements {
            var copy = el
            copy.id = UUID()
            copy.name = el.name + " copy"
            copy.xMm += 5
            copy.yMm += 5
            copy.zOrder = (page.elements.map(\.zOrder).max() ?? 0) + 1
            page.elements.append(copy)
            newIDs.insert(copy.id)
        }
        selectedElementIDs = newIDs
        selectedElementID = newIDs.first
        recomposePage()
    }

    func nudgeSelected(dx: Double, dy: Double, disableSnap: Bool = false) {
        let ids = selectedElementIDs.isEmpty ? Set([selectedElementID].compactMap { $0 }) : selectedElementIDs
        guard !ids.isEmpty else { return }
        checkpointDocument()
        for i in page.elements.indices where ids.contains(page.elements[i].id) && !page.elements[i].locked {
            var x = page.elements[i].xMm + dx
            var y = page.elements[i].yMm + dy
            let snapped = SnapEngine.snapPosition(
                x: x,
                y: y,
                page: page,
                elementSize: (page.elements[i].widthMm, page.elements[i].heightMm),
                disableSnap: disableSnap
            )
            x = snapped.x
            y = snapped.y
            page.elements[i].xMm = x
            page.elements[i].yMm = y
        }
        recomposePage()
    }

    private var geometryCheckpointTaken = false

    func beginGeometryEdit() {
        guard !geometryCheckpointTaken else { return }
        beginEditTransaction()
        geometryCheckpointTaken = true
    }

    func endGeometryEdit() {
        endEditTransaction()
        geometryCheckpointTaken = false
    }

    func updateSelectedGeometry(
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        rotation: Double? = nil,
        scale: Double? = nil,
        anchor: PageAnchor? = nil,
        lockAspect: Bool? = nil,
        checkpoint: Bool = true
    ) {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }),
              !page.elements[idx].locked else { return }
        if checkpoint { beginGeometryEdit() }
        if let x, let y {
            LayoutTools.setDisplayPosition(element: &page.elements[idx], page: page, x: x, y: y)
        } else {
            if let x { page.elements[idx].xMm = x }
            if let y { page.elements[idx].yMm = y }
        }
        if let width {
            if page.elements[idx].lockAspect {
                let ratio = page.elements[idx].heightMm / max(page.elements[idx].widthMm, 0.01)
                page.elements[idx].widthMm = max(1, width)
                page.elements[idx].heightMm = max(1, width * ratio)
            } else {
                page.elements[idx].widthMm = max(1, width)
            }
        }
        if let height, !(lockAspect ?? page.elements[idx].lockAspect) || width == nil {
            page.elements[idx].heightMm = max(1, height)
        }
        if let rotation { page.elements[idx].rotationDegrees = rotation }
        if let scale { page.elements[idx].scale = max(0.01, scale) }
        if let anchor { page.elements[idx].anchor = anchor }
        if let lockAspect { page.elements[idx].lockAspect = lockAspect }
        recomposePage()
    }

    func dragSelected(toPaperX x: Double, y: Double, disableSnap: Bool) {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }),
              !page.elements[idx].locked else { return }
        let snapped = SnapEngine.snapPosition(
            x: x,
            y: y,
            page: page,
            elementSize: (page.elements[idx].widthMm, page.elements[idx].heightMm),
            disableSnap: disableSnap
        )
        page.elements[idx].xMm = snapped.x
        page.elements[idx].yMm = snapped.y
        recomposePage()
    }

    func beginDragGesture() {
        beginGeometryEdit()
    }

    func centreSelected(horizontal: Bool, vertical: Bool) {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }) else { return }
        checkpointDocument()
        LayoutTools.centreOnPage(&page.elements[idx], page: page, horizontal: horizontal, vertical: vertical)
        recomposePage()
    }

    func alignSelection(horizontal: TextAlignment? = nil, vertical: LayoutTools.VerticalAlign? = nil) {
        let ids = Array(selectedElementIDs)
        guard ids.count >= 2 else { return }
        checkpointDocument()
        LayoutTools.align(&page.elements, ids: ids, page: page, horizontal: horizontal, vertical: vertical)
        recomposePage()
    }

    func distributeSelection(horizontal: Bool) {
        let ids = Array(selectedElementIDs)
        guard ids.count >= 3 else { return }
        checkpointDocument()
        LayoutTools.distribute(&page.elements, ids: ids, horizontal: horizontal)
        recomposePage()
    }

    func reorderSelected(action: (inout [PageElement], UUID) -> Void) {
        guard let id = selectedElementID else { return }
        checkpointDocument()
        action(&page.elements, id)
        recomposePage()
    }

    func toggleLockSelected() {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }) else { return }
        checkpointDocument()
        page.elements[idx].locked.toggle()
    }

    func toggleHideSelected() {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }) else { return }
        checkpointDocument()
        page.elements[idx].visible.toggle()
        recomposePage()
    }

    func renameSelected(_ name: String) {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }) else { return }
        beginEditTransaction()
        page.elements[idx].name = name
    }

    func commitRename() {
        endEditTransaction()
    }

    private var textEditCheckpointTaken = false

    func beginTextEditing() {
        guard !textEditCheckpointTaken else { return }
        beginEditTransaction()
        textEditCheckpointTaken = true
    }

    func endTextEditing() {
        // Only close a transaction that beginTextEditing opened — never an unrelated
        // geometry/rename transaction that happens to be open.
        guard textEditCheckpointTaken else { return }
        page.applyTextBoxSizing()
        endEditTransaction()
        textEditCheckpointTaken = false
        recomposePage()
    }

    func updateTextBox(text: String? = nil, style: TextBoxStyle? = nil) {
        guard let id = selectedElementID,
              let idx = page.elements.firstIndex(where: { $0.id == id }),
              case .textBox(let current, let currentStyle) = page.elements[idx].kind else { return }
        let nextStyle = style ?? currentStyle
        // Never silently fall back — refuse unimplemented options outright.
        if let style, !style.fontKind.isImplemented {
            lastError = "Outline fonts are not implemented yet."
            return
        }
        if let style, !style.overflowPolicy.isImplemented {
            lastError = "Truncate is not implemented — choose Show overflow, Expand box, or Reduce font."
            return
        }
        beginTextEditing()
        page.elements[idx].kind = .textBox(text: text ?? current, style: nextStyle)
        if let text { page.elements[idx].name = String(text.prefix(40)) }
        page.applyTextBoxSizing()
        recomposePage()
    }

    func addPenLayer() {
        checkpointDocument()
        let n = page.layers.count + 1
        let pens = PenPreset.library
        let pen = pens[(n - 1) % pens.count]
        let id = page.addLayer(named: "Pen \(n)", pen: pen)
        selectedLayerID = id
        recomposePage()
    }

    func duplicateSelectedLayer() {
        guard let id = selectedLayerID, let layer = page.layer(for: id) else { return }
        checkpointDocument()
        var copy = layer
        copy.id = UUID()
        copy.name = layer.name + " copy"
        copy.order = (page.layers.map(\.order).max() ?? 0) + 1
        page.layers.append(copy)
        selectedLayerID = copy.id
        recomposePage()
    }

    func saveProject(to url: URL? = nil) {
        let target = url ?? projectURL
        let panelURL: URL? = {
            if let target { return target }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "quill") ?? .json]
            panel.nameFieldStringValue = (page.name.isEmpty ? "Untitled" : page.name) + ".quill"
            return panel.runModal() == .OK ? panel.url : nil
        }()
        guard let dest = panelURL else { return }
        do {
            var project = currentProject
            project.touch()
            try project.save(to: dest)
            projectURL = dest
            UserDefaults.standard.set(dest.path, forKey: Self.lastProjectPathKey)
            rememberRecentProject(dest)
            try? FileManager.default.removeItem(at: autosaveURL())
            console.append("--- Saved project \(dest.lastPathComponent) ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "quill") ?? .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let project = try QuillProject.load(from: url)
            documentHistory.clear()
            applyProject(project, recordHistory: false)
            projectURL = url
            UserDefaults.standard.set(url.path, forKey: Self.lastProjectPathKey)
            rememberRecentProject(url)
            console.append("--- Opened \(url.lastPathComponent) ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func exportComposedSVG() {
        guard let job = composedPage?.job else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "\(page.name).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let svg = svgPreview(from: job)
        do {
            try svg.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func svgPreview(from job: PlotJob) -> String {
        var d = ""
        for cmd in job.commands {
            switch cmd {
            case .move(let p): d += "M \(p.x) \(machine.travelY - p.y) "
            case .line(let p): d += "L \(p.x) \(machine.travelY - p.y) "
            case .penChange: break
            }
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(machine.travelX)mm" height="\(machine.travelY)mm" viewBox="0 0 \(machine.travelX) \(machine.travelY)">
        <path d="\(d)" fill="none" stroke="black" stroke-width="0.3"/>
        </svg>
        """
    }

    private func rememberRecentProject(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: Self.recentProjectsKey) ?? []
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        if list.count > 12 { list = Array(list.prefix(12)) }
        UserDefaults.standard.set(list, forKey: Self.recentProjectsKey)
    }

    private func autosaveURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Quill", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(Self.autosaveName)
    }

    private func startAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performAutosave()
            }
        }
    }

    private func performAutosave() {
        var project = currentProject
        project.touch()
        try? project.save(to: autosaveURL())
    }

    private func recoverAutosaveIfNeeded() {
        let url = autosaveURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let autosaved = try? QuillProject.load(from: url),
              !autosaved.page.elements.isEmpty else { return }

        let autosaveDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate) ?? autosaved.modifiedAt

        if let path = UserDefaults.standard.string(forKey: Self.lastProjectPathKey) {
            let projectURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: projectURL.path),
               let saved = try? QuillProject.load(from: projectURL) {
                let savedDate = (try? projectURL.resourceValues(forKeys: [.contentModificationDateKey]))
                    .flatMap(\.contentModificationDate) ?? saved.modifiedAt
                // Only offer recovery when autosave is newer than the last saved project.
                guard autosaveDate > savedDate.addingTimeInterval(1) else { return }
                self.projectURL = projectURL
            }
        }

        pendingAutosaveRecovery = autosaved
        showAutosaveRecoveryAlert = true
    }

    func acceptAutosaveRecovery() {
        guard let project = pendingAutosaveRecovery else { return }
        documentHistory.clear()
        applyProject(project, recordHistory: false)
        pendingAutosaveRecovery = nil
        showAutosaveRecoveryAlert = false
        console.append("--- Recovered autosave ---")
    }

    func discardAutosaveRecovery() {
        pendingAutosaveRecovery = nil
        showAutosaveRecoveryAlert = false
        try? FileManager.default.removeItem(at: autosaveURL())
        console.append("--- Discarded autosave ---")
    }

    func recomposePage() {
        page.applyTextBoxSizing()
        do {
            var composePage = page
            if plotOnlySelectedLayer, let lid = selectedLayerID {
                composePage.layers = composePage.layers.map { layer in
                    var copy = layer
                    copy.visible = layer.id == lid
                    return copy
                }
            }
            let composed = try PageComposer.compose(composePage, profile: machine, optimize: optimizePaths)
            composedPage = composed
            previewJob = composed.job.simplified()
            jobText = composed.gcode
            jobName = page.name
            runner.loadGCode(jobText)
            preflightReport = JobPreflight.assess(
                gcode: jobText,
                profile: machine,
                machineState: status.state,
                workZeroKnown: workZeroKnown,
                isBusy: isBusyBlockingJob
            )
            if composed.hasBlockingOverflow {
                lastError = composed.warnings.first ?? "Text overflow — resolve before plotting"
            }
        } catch {
            composedPage = nil
            // Keep last good preview; surface error.
            lastError = error.localizedDescription
        }
    }

    func applyPageToJob() {
        if let msg = pageFitBlockingMessage {
            lastError = msg
            return
        }
        recomposePage()
        guard let composed = composedPage else { return }
        // Text overflow is never bypassed by allowStartDespiteWarnings.
        if composed.hasBlockingOverflow || page.hasTextOverflow() {
            lastError = "Resolve text overflow before plotting. This cannot be bypassed."
            return
        }
        mode = .run
    }

    func framePage() {
        recomposePage()
        guard let composed = composedPage else { return }
        loadJob(text: composed.frameGCode, name: "Frame-\(page.format.id).gcode", isSVG: false)
        mode = .run
    }

    func importCSVForBatch() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let csv = UTType(filenameExtension: "csv") { types.insert(csv, at: 0) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = VariableData.parseCSV(text)
            csvHeaders = parsed.headers
            var map: [UUID: String] = [:]
            for el in page.elements {
                switch el.kind {
                case .text(let raw, _) where raw.contains("{"):
                    map[el.id] = raw
                case .textBox(let raw, _) where raw.contains("{"):
                    map[el.id] = raw
                default:
                    break
                }
            }
            batch = VariableData.makeBatch(
                template: page,
                fieldMap: map,
                rows: parsed.rows,
                pauseBetweenPages: true
            )
            let overflowCount = batch.pages.filter(\.overflows).count
            console.append("--- Batch: \(parsed.rows.count) page(s) from \(url.lastPathComponent); \(overflowCount) overflow warning(s) ---")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func previewBatchPage(_ pageID: UUID) {
        guard let material = VariableData.materialize(batch: batch, pageID: pageID) else { return }
        page = material
        selectedLayerID = page.defaultLayerID
        recomposePage()
    }

    func skipBatchPage(_ pageID: UUID) {
        guard let idx = batch.pages.firstIndex(where: { $0.id == pageID }) else { return }
        batch.pages[idx].status = .skipped
    }

    func queueNextBatchPage() {
        guard let next = batch.pages.first(where: {
            $0.status == .ready || $0.status == .pending || $0.status == .pausedForPaper
        }) else {
            lastError = "Batch queue is empty"
            return
        }
        // Re-validate this record before entering plotting.
        batch.pages = VariableData.validateRecords(batch: batch)
        guard let idx = batch.pages.firstIndex(where: { $0.id == next.id }) else { return }
        let record = batch.pages[idx]
        if VariableData.isBlocked(record) {
            batch.pages[idx].status = .failed
            let reason = record.errorMessage ?? "Overflow or missing fields"
            batch.pages[idx].errorMessage = reason
            lastError = "Batch record #\(record.index + 1) blocked: \(reason)"
            previewBatchPage(record.id)
            return
        }
        previewBatchPage(record.id)
        // Block if the materialized page still overflows.
        if hasBlockingTextOverflow {
            batch.pages[idx].status = .failed
            batch.pages[idx].errorMessage = lastError ?? "Text overflow"
            lastError = "Batch record #\(record.index + 1) blocked: \(batch.pages[idx].errorMessage ?? "overflow")"
            return
        }
        batch.pages[idx].status = .plotting
        batch.currentIndex = idx
        applyPageToJob()
    }

    func markCurrentBatchPageCompleted() {
        guard !batch.pages.isEmpty,
              batch.pages.indices.contains(batch.currentIndex),
              batch.pages[batch.currentIndex].status == .plotting else { return }
        batch.pages[batch.currentIndex].status = .completed
        if batch.pauseBetweenPages,
           let next = batch.pages.first(where: { $0.status == .ready || $0.status == .pending }) {
            if let idx = batch.pages.firstIndex(where: { $0.id == next.id }) {
                batch.pages[idx].status = .pausedForPaper
            }
            penChangeMessage = "Page done — replace paper, then Queue next page"
        }
    }

    func applyInkToJob() {
        inkDocument.travelX = machine.travelX
        inkDocument.travelY = machine.travelY
        let job = inkDocument.plotJob()
        guard !job.commands.isEmpty else {
            lastError = "Draw at least one ink stroke first"
            return
        }
        previewJob = job.simplified()
        jobText = SVGToGCode.gcode(from: job, profile: machine)
        jobName = "Ink.gcode"
        jobURL = nil
        runner.loadGCode(jobText)
        streamProgress = 0
        streamState = .idle
        console.append("--- Ink job: \(inkDocument.strokes.count) stroke(s), pressure→Z ---")
    }

    func clearInk() {
        inkDocument = InkDocument(travelX: machine.travelX, travelY: machine.travelY)
    }

    func saveInkDocument() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "handwriting.ta4ink"
        if let ut = UTType(filenameExtension: "ta4ink") {
            panel.allowedContentTypes = [ut, .json]
        } else {
            panel.allowedContentTypes = [.json]
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try inkDocument.jsonData().write(to: url)
                console.append("--- Saved ink: \(url.lastPathComponent) ---")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func exportInkSVG() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "handwriting.svg"
        panel.allowedContentTypes = [.svg]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try inkDocument.exportSVG().write(to: url, atomically: true, encoding: .utf8)
                console.append("--- Exported ink SVG: \(url.lastPathComponent) ---")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func loadInkDocument(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            inkDocument = try InkDocument.load(from: data)
            showInkCanvas = true
            applyInkToJob()
            rememberRecent(url)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Jog a short XY segment while stepping Z across the pressure range for calibration.
    func testPressureSweep() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        machine.clampPressureRange()
        persistMachine()
        let light = machine.pressureMinZ
        let hard = machine.pressureMaxZ
        let steps = 5
        let coordinator = self.coordinator
        let machine = self.machine
        Task.detached(priority: .userInitiated) {
            do {
                try coordinator.penUp(machine)
                try coordinator.sendManualLine("G90 G0 X10 Y10")
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let z = light + (hard - light) * t
                    try coordinator.sendManualLine(String(format: "G1 Z%.3f F%.3f", z, machine.drawFeed))
                    try coordinator.sendManualLine(String(format: "G1 X%.3f Y10 F%.3f", 10 + Double(i) * 8, machine.drawFeed))
                    Thread.sleep(forTimeInterval: 0.15)
                }
                try coordinator.penUp(machine)
                await MainActor.run {
                    self.console.append(String(
                        format: "--- Pressure sweep Z %.2f → %.2f complete ---",
                        light, hard
                    ))
                }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    private func applyJobText(_ text: String, isSVG: Bool) {
        do {
            if isSVG {
                let job = try SVGToGCode.plotJob(
                    from: text,
                    profile: machine,
                    placement: svgPlacement,
                    offsetX: svgOffsetX,
                    offsetY: svgOffsetY
                )
                previewJob = job.simplified()
                jobText = SVGToGCode.gcode(from: job, profile: machine)
            } else {
                let normalized = GCodeNormalizer.normalizePenCommands(text, profile: machine)
                jobText = normalized.text
                if normalized.substitutions > 0 {
                    console.append("--- Normalized \(normalized.substitutions) pen M3/M5/SM03 → Z moves ---")
                }
                previewJob = GCodeParser.parse(
                    jobText,
                    defaultFeed: machine.drawFeed,
                    defaultRapid: machine.jogFeed
                ).plotJob.simplified()
            }
            runner.loadGCode(jobText)
            streamProgress = 0
            streamState = .idle
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runPreflight() {
        try? coordinator.requestStatus()
        preflightReport = JobPreflight.assess(
            gcode: jobText,
            profile: machine,
            machineState: status.state,
            workZeroKnown: workZeroKnown,
            isBusy: isBusyBlockingJob
        )
    }

    func frameJob() {
        let parse = preflightReport?.parse
            ?? GCodeParser.parse(jobText, defaultFeed: machine.drawFeed, defaultRapid: machine.jogFeed)
        let gcode = JobPreflight.frameGCode(bounds: parse.bounds, profile: machine)
        loadJob(text: gcode, name: "Frame.gcode", isSVG: false)
    }

    func startJob() {
        guard isConnected else {
            lastError = "Connect first"
            return
        }
        if let msg = pageFitBlockingMessage {
            lastError = msg
            return
        }
        // Text overflow is a hard blocker and cannot be bypassed by allowStartDespiteWarnings.
        if hasBlockingTextOverflow {
            lastError = "Resolve text overflow before plotting. This cannot be bypassed."
            return
        }
        try? coordinator.requestStatus()
        let report = JobPreflight.assess(
            gcode: jobText,
            profile: machine,
            machineState: status.state,
            workZeroKnown: workZeroKnown,
            isBusy: isBusyBlockingJob
        )
        preflightReport = report
        if !report.okToStart {
            lastError = report.issues.first(where: { $0.severity == .error })?.message
                ?? "Preflight failed"
            return
        }
        // Soft preflight warnings may be allowed; text overflow never is.
        penChangeMessage = nil
        runner.loadGCode(jobText)
        do {
            try runner.start()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pauseJob() { runner.pause() }
    func resumeJob() {
        if streamState == .waitingForPenChange {
            penChangeMessage = nil
        }
        runner.resume()
    }
    func cancelJob() {
        penChangeMessage = nil
        runner.cancel()
    }

    func setWatchJobFile(_ enabled: Bool) {
        watchJobFile = enabled
        if watchJobFile {
            startFileWatchIfNeeded()
        } else {
            stopFileWatch()
        }
    }

    private func rememberRecent(_ url: URL) {
        var list = recentJobs.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        recentJobs = list
        UserDefaults.standard.set(list, forKey: Self.recentKey)
    }

    private func updateStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
        guard isConnected else { return }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                if self.streamState == .running || self.streamState == .paused
                    || self.streamState == .waitingForPenChange {
                    self.requestStatus()
                }
            }
        }
    }

    private func startFileWatchIfNeeded() {
        stopFileWatch()
        guard watchJobFile, let url = jobURL else { return }
        let path = url.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileWatchFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let url = self.jobURL else { return }
            self.loadJob(url: url)
            self.console.append("--- Reloaded \(url.lastPathComponent) after save ---")
        }
        source.setCancelHandler {
            close(fd)
        }
        fileWatchSource = source
        source.resume()
    }

    private func stopFileWatch() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
        fileWatchFD = -1
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

    var shortLabel: String {
        switch self {
        case .x: return "X"
        case .y: return "Y"
        }
    }

    var prompt: String {
        switch self {
        case .x: return "along the left–right axis"
        case .y: return "along the front–back axis"
        }
    }
}
