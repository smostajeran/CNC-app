import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var consoleInput = ""

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            Group {
                switch model.mode {
                case .setup: setupMode
                case .create: createMode
                case .run: runMode
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if model.isJobActiveLike {
                    Button("Hold") { model.pauseJob() }
                    Button("Resume") { model.resumeJob() }
                    Button("Stop", role: .destructive) { model.cancelJob() }
                } else {
                    Button("Refresh Ports") { model.refreshPorts() }
                        .disabled(!model.allowsManualCommands && model.isConnected)
                }
            }
        }
        .onAppear { model.refreshPorts() }
        .onOpenURL { url in model.loadJob(url: url) }
        .alert("Error", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .sheet(isPresented: $model.showCalibrationWizard) {
            CalibrationWizardView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 520)
        }
    }

    private var modeBar: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $model.mode) {
                Text("Setup").tag(QuillMode.setup)
                Text("Create & Position").tag(QuillMode.create)
                Text("Run").tag(QuillMode.run)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer()

            connectionChip

            Toggle("Diagnostics", isOn: $model.showDiagnostics)
                .toggleStyle(.switch)
                .labelsHidden()
            Text("Diagnostics")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var connectionChip: some View {
        let label: String = {
            switch model.connectionState {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected: return "\(model.status.state) · \(fmt(model.status.mpos.x)), \(fmt(model.status.mpos.y))"
            case .fault(let msg): return "Fault: \(msg)"
            }
        }()
        return Text(label)
            .font(.caption.monospaced())
            .foregroundStyle(model.isConnected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(model.isConnected ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - Setup

    private var setupMode: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTitle("1. Connect", subtitle: "Identify the controller before moving or calibrating.")
                    ConnectPane()
                    sectionTitle("2. Origin & axes", subtitle: "Set work zero, then calibrate scale so 10 mm = 10 mm.")
                    ControlPane()
                    Button("Axis scale wizard…") {
                        model.setCalibrationWizardOpen(true)
                    }
                    .disabled(!model.isConnected || !model.allowsManualCommands)
                    Text("Mark two points per axis, measure, write $100/$101 with read-back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sectionTitle("3. Pen pressure", subtitle: "Motor Z depth stands in for force on the TA-4.")
                    SettingsPane()
                }
                .padding(20)
                .frame(maxWidth: 420, alignment: .leading)
            }
            .frame(minWidth: 340)

            if model.showDiagnostics {
                diagnosticsPane
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Setup checklist")
                        .font(.title2.weight(.semibold))
                    checklistRow(model.isConnected, "Connected over USB")
                    checklistRow(model.machine.stepsPerMmX != nil && model.machine.stepsPerMmY != nil, "Probed steps/mm ($100/$101)")
                    checklistRow(model.workZeroKnown, "Work zero set this session")
                    Text("When ready, switch to Create & Position to load a job.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Create

    private var createMode: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("Import", subtitle: "SVG, G-code, text, or handwriting.")
                    HStack {
                        Button("Open…") { openFile() }
                        Button("Paste") { model.pasteFromClipboard() }
                        Button("Inkscape Template…") { model.exportInkscapeTemplate() }
                    }
                    Picker("SVG placement", selection: $model.svgPlacement) {
                        ForEach(SVGPlacementMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    if model.svgPlacement == .custom {
                        HStack {
                            Text("Offset X")
                            TextField("", value: $model.svgOffsetX, format: .number)
                                .frame(width: 60)
                            Text("Y")
                            TextField("", value: $model.svgOffsetY, format: .number)
                                .frame(width: 60)
                        }
                        .font(.caption)
                    }
                    Text("Original size preserves authored mm and rejects out-of-bed paths instead of clamping.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TextPane()
                    InkPane()

                    if !model.recentJobs.isEmpty {
                        Text("Recent")
                            .font(.headline)
                        ForEach(model.recentJobs, id: \.self) { path in
                            Button(URL(fileURLWithPath: path).lastPathComponent) {
                                model.loadJob(url: URL(fileURLWithPath: path))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .frame(minWidth: 280, maxWidth: 320, alignment: .leading)
            }

            VStack(spacing: 0) {
                JobPane(showRunControls: false)
                if model.showDiagnostics {
                    Divider()
                    diagnosticsPane.frame(minHeight: 160)
                }
            }
        }
    }

    // MARK: - Run

    private var runMode: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.jobName)
                        .font(.title2.weight(.semibold))
                    Text(streamLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ProgressView(value: model.streamProgress)
                    if let msg = model.penChangeMessage {
                        Text(msg)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if let report = model.preflightReport {
                        preflightSummary(report)
                    }
                    HStack {
                        Button("Preflight") { model.runPreflight() }
                            .disabled(model.jobText.isEmpty)
                        Button("Frame Job") { model.frameJob() }
                            .disabled(!model.isConnected || model.jobText.isEmpty || !model.allowsManualCommands)
                        Button("Start") {
                            model.startJob()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.isConnected || model.jobText.isEmpty || model.isJobActiveLike)
                        Button("Hold") { model.pauseJob() }
                            .disabled(!model.isJobActiveLike)
                        Button("Resume") { model.resumeJob() }
                            .disabled(!(model.streamState == .paused || model.streamState == .waitingForPenChange))
                        Button("Stop", role: .destructive) { model.cancelJob() }
                            .disabled(!model.isJobActiveLike)
                    }
                    Text(String(
                        format: "Head MPos %.2f, %.2f, %.2f",
                        model.status.mpos.x, model.status.mpos.y, model.status.mpos.z
                    ))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
                .frame(width: 360, alignment: .leading)
                .padding(16)

                PathPreviewView(job: model.previewJob, workspace: model.machine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(12)
            }

            if model.showDiagnostics {
                Divider()
                diagnosticsPane.frame(minHeight: 140)
            }
        }
    }

    private func preflightSummary(_ report: JobPreflightReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preflight · ETA \(report.estimatedRuntimeLabel) · \(report.parse.penChangeCount) pen change(s)")
                .font(.caption.weight(.semibold))
            ForEach(report.issues.prefix(6)) { issue in
                Text("• \(issue.message)")
                    .font(.caption2)
                    .foregroundStyle(issue.severity == .error ? Color.red : (issue.severity == .warning ? Color.orange : Color.secondary))
            }
            if report.okToStart {
                Text("Ready to start")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var diagnosticsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Diagnostics")
                .font(.headline)
                .padding(8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.console.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.console.count) { _ in
                    if let last = model.console.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            HStack {
                TextField("Send G-code / $$ / $I", text: $consoleInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendConsole() }
                    .disabled(!model.allowsManualCommands)
                Button("Send") { sendConsole() }
                    .disabled(!model.isConnected || consoleInput.isEmpty || !model.allowsManualCommands)
            }
            .padding(8)
            if !model.allowsManualCommands {
                Text("Manual commands locked while a job owns the serial port.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func checklistRow(_ ok: Bool, _ text: String) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ok ? Color.green : Color.secondary)
            .font(.callout)
    }

    private var streamLabel: String {
        switch model.streamState {
        case .idle: return "Ready — run Preflight, then Start"
        case .running: return String(format: "Streaming %.0f%% (acked)", model.streamProgress * 100)
        case .paused: return "Hold"
        case .waitingForPenChange: return "Waiting for pen change"
        case .completed: return "Completed (Idle)"
        case .cancelled: return "Cancelled"
        case .fault(let m): return "Fault: \(m)"
        }
    }

    private func sendConsole() {
        let line = consoleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        model.sendConsole(line)
        consoleInput = ""
    }

    private func openFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.svg, .json]
        if let nc = UTType(filenameExtension: "nc") { types.append(nc) }
        if let gcode = UTType(filenameExtension: "gcode") { types.append(gcode) }
        if let ngc = UTType(filenameExtension: "ngc") { types.append(ngc) }
        if let ink = UTType(filenameExtension: "ta4ink") { types.append(ink) }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            model.loadJob(url: url)
        }
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}

private extension AppModel {
    var isJobActiveLike: Bool {
        switch streamState {
        case .running, .paused, .waitingForPenChange: return true
        default: return false
        }
    }
}

struct ConnectPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Port", selection: $model.selectedPort) {
                Text("None").tag(String?.none)
                ForEach(model.ports) { port in
                    Text(port.name).tag(Optional(port.path))
                }
            }
            HStack {
                Text("Baud")
                TextField("", value: $model.baudRate, format: .number)
                    .frame(width: 90)
            }
            HStack {
                if model.isConnected {
                    Button("Disconnect") { model.disconnect() }
                } else {
                    Button("Connect") { model.connect() }
                        .keyboardShortcut(.defaultAction)
                }
                Button("Probe $$/$I") { model.probe() }
                    .disabled(!model.isConnected || !model.allowsManualCommands)
            }
            HStack {
                Button("Soft Reset") { model.softReset() }
                    .disabled(!model.isConnected || !model.allowsManualCommands)
                Button("Unlock $X") { model.unlock() }
                    .disabled(!model.isConnected || !model.allowsManualCommands)
            }
            if let build = model.machine.buildInfo, !build.isEmpty {
                Text(build)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text("Workspace \(Int(model.machine.travelX))×\(Int(model.machine.travelY)) mm")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let sx = model.machine.stepsPerMmX, let sy = model.machine.stepsPerMmY {
                Text(String(format: "Steps/mm X %.3f · Y %.3f", sx, sy))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Invert X", isOn: $model.machine.invertX)
            Toggle("Invert Y", isOn: $model.machine.invertY)
            Toggle("Invert Z", isOn: $model.machine.invertZ)
            labeledField("Pen up Z", value: $model.machine.penUpZ)
            labeledField("Pen down Z", value: $model.machine.penDownZ)
            labeledField("Light Z", value: $model.machine.pressureMinZ)
            labeledField("Hard Z", value: $model.machine.pressureMaxZ)
            Button("Test pressure sweep") { model.testPressureSweep() }
                .disabled(!model.isConnected || !model.allowsManualCommands)
            labeledField("Jog feed", value: $model.machine.jogFeed)
            labeledField("Draw feed", value: $model.machine.drawFeed)
        }
        .disabled(!model.allowsManualCommands && model.isConnected)
        .onChange(of: model.machine) { _ in
            model.persistMachine()
        }
    }

    private func labeledField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            TextField("", value: value, format: .number).frame(width: 80)
        }
        .font(.caption)
    }
}

struct InkPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show ink canvas", isOn: $model.showInkCanvas)
            Text("Stylus pressure → Z (smoothed). Trackpad uses speed proxy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("Use as job") { model.applyInkToJob() }
                Button("Clear") { model.clearInk() }
            }
            HStack {
                Button("Save .ta4ink…") { model.saveInkDocument() }
                Button("Export SVG…") { model.exportInkSVG() }
            }
        }
    }
}

struct ControlPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Step", selection: $model.jogStep) {
                Text("1 mm").tag(1.0)
                Text("5 mm").tag(5.0)
                Text("10 mm").tag(10.0)
                Text("50 mm").tag(50.0)
            }
            .pickerStyle(.segmented)
            .disabled(!model.isConnected || !model.allowsManualCommands)

            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Button("Y+") { model.jog(dx: 0, dy: model.jogStep) }
                    HStack {
                        Button("X−") { model.jog(dx: -model.jogStep, dy: 0) }
                        Button("X+") { model.jog(dx: model.jogStep, dy: 0) }
                    }
                    Button("Y−") { model.jog(dx: 0, dy: -model.jogStep) }
                }
                .disabled(!model.isConnected || !model.allowsManualCommands)
                Spacer()
            }

            HStack {
                Button("Pen Up") { model.penUp() }
                Button("Pen Down") { model.penDown() }
            }
            .disabled(!model.isConnected || !model.allowsManualCommands)

            HStack {
                Button("Set Zero") { model.setWorkZero() }
                Button("Go Origin") { model.goToOrigin() }
            }
            .disabled(!model.isConnected || !model.allowsManualCommands)
        }
    }
}

struct TextPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text").font(.headline)
            TextField("Text", text: $model.textInput)
            HStack {
                Text("Height mm")
                TextField("", value: $model.textHeightMm, format: .number)
                    .frame(width: 60)
            }
            Button("Generate text job") { model.generateTextJob() }
        }
    }
}

struct JobPane: View {
    @EnvironmentObject private var model: AppModel
    var showRunControls: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.jobName).font(.headline)
                Spacer()
                if showRunControls {
                    Button("Start") { model.startJob() }
                        .disabled(!model.isConnected || model.jobText.isEmpty)
                    Button("Pause") { model.pauseJob() }
                    Button("Resume") { model.resumeJob() }
                    Button("Cancel") { model.cancelJob() }
                } else {
                    Button("Preflight") { model.runPreflight() }
                        .disabled(model.jobText.isEmpty)
                    Button("Go to Run") { model.mode = .run }
                        .disabled(model.jobText.isEmpty)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if showRunControls {
                ProgressView(value: model.streamProgress)
                    .padding(.horizontal, 8)
            }

            if model.showInkCanvas {
                InkCanvasView(
                    document: $model.inkDocument,
                    workspace: model.machine,
                    onStrokeEnd: { model.applyInkToJob() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(8)
            } else {
                PathPreviewView(job: model.previewJob, workspace: model.machine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(8)
                    .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: nil) { providers in
                        handleDrop(providers)
                    }
            }

            TextEditor(text: Binding(
                get: { model.jobText },
                set: { model.updateJobText($0) }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 100, idealHeight: 140)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = {
                        if let data = item as? Data {
                            return URL(dataRepresentation: data, relativeTo: nil)
                        }
                        if let url = item as? URL { return url }
                        return nil
                    }()
                    guard let url else { return }
                    Task { @MainActor in model.loadJob(url: url) }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let str = obj as? String else { return }
                    Task { @MainActor in
                        let isSVG = str.contains("<svg")
                        model.loadJob(text: str, name: isSVG ? "Dropped.svg" : "Dropped.gcode", isSVG: isSVG)
                    }
                }
                return true
            }
        }
        return false
    }
}
