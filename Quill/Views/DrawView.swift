import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

struct DrawView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Draw")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Open a drawing or handwriting, preview the path, then start — or continue to Compose for true-size pages.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(.secondary)
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
                            Button("Start") { model.startJob() }
                                .disabled(!model.isConnected || model.jobText.isEmpty)
                            Button("Hold") { model.pauseJob() }
                            Button("Resume") { model.resumeJob() }
                            Button("Cancel") { model.cancelJob() }
                            Spacer()
                            Text(streamLabel)
                                .font(Theme.captionFont)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: model.streamProgress)
                            .tint(Theme.steelBright)

                        if model.showInkCanvas {
                            InkCanvasView(
                                document: $model.inkDocument,
                                workspace: model.machine,
                                onStrokeEnd: { model.applyInkToJob() }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .quillGlass(shape: .rect(cornerRadius: 16))
                        } else {
                            PathPreviewView(job: model.previewJob, workspace: model.machine)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .quillGlass(shape: .rect(cornerRadius: 16))
                        }

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
    }

    private var streamLabel: String {
        switch model.streamState {
        case .idle: return "Ready"
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
