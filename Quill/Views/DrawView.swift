import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

struct DrawView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: (() -> Void)? = nil
    @State private var confirmStart = false

    private var hasJob: Bool { !model.jobText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Draw")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Open a drawing or handwriting, preview the path, then start — or continue to Compose for true-size pages.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                GlassChip(tint: Theme.steel.opacity(0.2)) {
                    Text(model.jobName)
                        .font(Theme.captionFont.weight(.medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            if !model.isConnected {
                HelpCard(
                    title: "Connect first",
                    message: "Finish Setup before starting a drawing.",
                    tone: .caution
                )
                .padding(.horizontal, 28)
            }

            GlassEffectContainer {
                GlassPanel(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button("Open drawing…") { openFile() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.steel)
                            Button("Paste") { model.pasteFromClipboard() }
                            Button("Ink canvas") { model.showInkCanvas.toggle() }
                            Button("Start") { confirmStart = true }
                                .disabled(!model.isConnected || !hasJob)
                            Button("Hold") { model.pauseJob() }
                            Button("Resume") { model.resumeJob() }
                            Button("Cancel") { model.cancelJob() }
                            EmergencyStopButton(compact: true)
                            Spacer()
                            Text(streamLabel)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.inkMuted)
                        }

                        ProgressView(value: model.streamProgress)
                            .tint(Theme.steelBright)

                        ZStack {
                            if model.showInkCanvas {
                                InkCanvasView(
                                    document: $model.inkDocument,
                                    workspace: model.machine,
                                    onStrokeEnd: { model.applyInkToJob() }
                                )
                            } else if hasJob {
                                PathPreviewView(job: model.previewJob, workspace: model.machine)
                            } else {
                                EmptyCanvasHint(
                                    title: "No drawing loaded",
                                    message: "Open an SVG or G-code file, paste from the clipboard, or sketch on the ink canvas.",
                                    primaryTitle: "Open drawing…",
                                    primaryAction: { openFile() },
                                    secondaryTitle: "Ink canvas",
                                    secondaryAction: { model.showInkCanvas = true }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .quillGlass(shape: .rect(cornerRadius: 16))

                        if let onContinue {
                            HStack {
                                Spacer()
                                Button("Continue to Compose") { onContinue() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.steel)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            DisclosureGroup("Show drawing code (optional)") {
                TextEditor(text: Binding(
                    get: { model.jobText },
                    set: { model.updateJobText($0) }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 100, idealHeight: 140)
                .padding(.top, 8)
            }
            .font(Theme.captionFont)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .confirmationDialog(
            "Start this drawing on the plotter?",
            isPresented: $confirmStart,
            titleVisibility: .visible
        ) {
            Button("Start drawing") { model.startJob() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep clear of the moving carriage. Preflight runs automatically before streaming.")
        }
    }

    private var streamLabel: String {
        switch model.streamState {
        case .idle: return hasJob ? "Ready" : "Load a drawing"
        case .running: return String(format: "Drawing %.0f%%", model.streamProgress * 100)
        case .paused: return "Hold"
        case .waitingForPenChange: return "Waiting for pen change"
        case .completed: return "Done"
        case .cancelled: return "Cancelled"
        case .fault(let m): return "Problem: \(m)"
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
        if panel.runModal() == .OK, let url = panel.url {
            model.loadJob(url: url)
        }
    }
}
