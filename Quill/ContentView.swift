import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var consoleInput = ""

    var body: some View {
        NavigationSplitView {
            List {
                Section("Machine") {
                    ConnectPane()
                }
                Section("Settings") {
                    SettingsPane()
                }
                Section("Control") {
                    ControlPane()
                }
                Section("Calibrate") {
                    Button("Axis scale wizard…") {
                        model.showCalibrationWizard = true
                    }
                    Text("Mark two points per axis, measure, adjust so 10 mm = 10 mm.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let sx = model.machine.stepsPerMmX, let sy = model.machine.stepsPerMmY {
                        Text(String(format: "Steps/mm X %.2f · Y %.2f", sx, sy))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Text") {
                    TextPane()
                }
                Section("Ink") {
                    InkPane()
                }
                if !model.recentJobs.isEmpty {
                    Section("Recent") {
                        ForEach(model.recentJobs, id: \.self) { path in
                            Button(URL(fileURLWithPath: path).lastPathComponent) {
                                model.loadJob(url: URL(fileURLWithPath: path))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 300)
        } detail: {
            HSplitView {
                JobPane()
                    .frame(minWidth: 360)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Console")
                        .font(.headline)
                        .padding(8)
                    if let msg = model.penChangeMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                    }
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
                        Button("Send") { sendConsole() }
                            .disabled(!model.isConnected || consoleInput.isEmpty)
                    }
                    .padding(8)
                }
                .frame(minWidth: 280)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh Ports") { model.refreshPorts() }
                Button("Paste Job") { model.pasteFromClipboard() }
                Button("Inkscape Template…") { model.exportInkscapeTemplate() }
                Button("Status") { model.requestStatus() }
                    .disabled(!model.isConnected)
                Button("Halt", role: .destructive) { model.halt() }
                    .disabled(!model.isConnected)
            }
        }
        .onAppear { model.refreshPorts() }
        .onOpenURL { url in
            model.loadJob(url: url)
        }
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

    private func sendConsole() {
        let line = consoleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        model.sendConsole(line)
        consoleInput = ""
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
                    .disabled(!model.isConnected)
            }
            HStack {
                Button("Soft Reset") { model.softReset() }
                    .disabled(!model.isConnected)
                Button("Unlock $X") { model.unlock() }
                    .disabled(!model.isConnected)
            }
            statusLine
            if let build = model.machine.buildInfo, !build.isEmpty {
                Text(build)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text("Workspace \(Int(model.machine.travelX))×\(Int(model.machine.travelY)) mm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        let label: String = {
            switch model.connectionState {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected · \(model.status.state)"
            case .fault(let msg): return "Fault: \(msg)"
            }
        }()
        Text(label)
            .font(.caption)
            .foregroundStyle(model.isConnected ? .green : .secondary)
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
            Text("Pressure: light Z higher, hard Z lower (clamped)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Test pressure sweep") { model.testPressureSweep() }
                .disabled(!model.isConnected)
            labeledField("Jog feed", value: $model.machine.jogFeed)
            labeledField("Draw feed", value: $model.machine.drawFeed)
            Toggle("Watch job file (Inkscape reload)", isOn: Binding(
                get: { model.watchJobFile },
                set: { model.setWatchJobFile($0) }
            ))
        }
        .padding(.vertical, 4)
        .onChange(of: model.machine) { _ in
            model.persistMachine()
        }
    }

    private func labeledField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 90, alignment: .leading)
            TextField("", value: value, format: .number)
                .frame(width: 80)
        }
        .font(.caption)
    }
}

struct InkPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show ink canvas", isOn: $model.showInkCanvas)
            Text("Stylus pressure → Z. Trackpad uses speed proxy.")
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
            Text("\(model.inkDocument.strokes.count) stroke(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
            .disabled(!model.isConnected)

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
                .disabled(!model.isConnected)
                Spacer()
            }

            HStack {
                Button("Pen Up") { model.penUp() }
                Button("Pen Down") { model.penDown() }
            }
            .disabled(!model.isConnected)

            HStack {
                Button("Set Zero") { model.setWorkZero() }
                Button("Go Origin") { model.goToOrigin() }
            }
            .disabled(!model.isConnected)

            Text("MPos \(fmt(model.status.mpos.x)), \(fmt(model.status.mpos.y)), \(fmt(model.status.mpos.z))")
                .font(.system(.caption, design: .monospaced))
        }
        .padding(.vertical, 4)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}

struct TextPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Text", text: $model.textInput)
            HStack {
                Text("Height mm")
                TextField("", value: $model.textHeightMm, format: .number)
                    .frame(width: 60)
            }
            Button("Generate text job") { model.generateTextJob() }
        }
        .padding(.vertical, 4)
    }
}

struct JobPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.jobName)
                    .font(.headline)
                Spacer()
                Button("Open…") { openFile() }
                Button("Start") { model.startJob() }
                    .disabled(!model.isConnected || model.jobText.isEmpty)
                Button("Pause") { model.pauseJob() }
                Button("Resume") { model.resumeJob() }
                Button("Cancel") { model.cancelJob() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ProgressView(value: model.streamProgress)
                .padding(.horizontal, 8)
            Text(streamLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

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
            .frame(minHeight: 120, idealHeight: 160)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var streamLabel: String {
        switch model.streamState {
        case .idle: return "Ready — drop SVG/G-code or Paste Job"
        case .running: return String(format: "Streaming %.0f%%", model.streamProgress * 100)
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .fault(let m): return "Fault: \(m)"
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.svg, .json]
        if let nc = UTType(filenameExtension: "nc") { types.append(nc) }
        if let gcode = UTType(filenameExtension: "gcode") { types.append(gcode) }
        if let ngc = UTType(filenameExtension: "ngc") { types.append(ngc) }
        if let ink = UTType(filenameExtension: "ta4ink") { types.append(ink) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.loadJob(url: url)
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
                    Task { @MainActor in
                        model.loadJob(url: url)
                    }
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
