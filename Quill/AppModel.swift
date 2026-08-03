import Foundation
import Combine
import AppKit
import CNCCore
import UniformTypeIdentifiers

enum QuillMode: String, CaseIterable {
    case setup, create, run
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

    @Published var mode: QuillMode = .setup
    @Published var showDiagnostics = false
    @Published var workZeroKnown = false
    @Published var svgPlacement: SVGPlacementMode = .originalSize
    @Published var svgOffsetX = 0.0
    @Published var svgOffsetY = 0.0
    @Published var preflightReport: JobPreflightReport?
    @Published var busyReason: MachineBusyReason?
    @Published var allowStartDespiteWarnings = false

    private let client = GRBLClient()
    private let coordinator: CommandCoordinator
    private let runner = JobRunner()
    private var previewTask: Task<Void, Never>?
    private var statusTimer: Timer?
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileWatchFD: Int32 = -1

    private static let recentKey = "quill.recentJobs"
    private static let portKey = "quill.lastPort"
    private static let baudKey = "quill.lastBaud"

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var allowsManualCommands: Bool { coordinator.allowsManualCommands }

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
        guard let selectedPort else {
            lastError = "Select a serial port"
            return
        }
        lastError = nil
        connectionState = .connecting
        UserDefaults.standard.set(selectedPort, forKey: Self.portKey)
        UserDefaults.standard.set(baudRate, forKey: Self.baudKey)
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
        switch streamState {
        case .running, .paused, .waitingForPenChange:
            runner.cancel()
        default:
            break
        }
        coordinator.endStreaming()
        client.disconnect()
        connectionState = .disconnected
        updateStatusPolling()
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
    func halt() {
        runner.cancel()
        try? coordinator.halt()
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

    func goToOrigin() {
        do {
            try coordinator.goToOrigin(machine: machine)
        } catch {
            lastError = error.localizedDescription
        }
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
                    self.persistMachine()
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
            try coordinator.jog(dx: dx, dy: dy, dz: dz, feed: machine.jogFeed, machine: machine)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func penUp() { try? coordinator.penUp(machine) }
    func penDown() { try? coordinator.penDown(machine) }

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
        let pos = status.wpos != .zero ? status.wpos : status.mpos
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
        // Warnings are surfaced via preflightReport for UI; only errors block Start.
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
