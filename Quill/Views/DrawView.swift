import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

struct DrawView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Draw")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Open a drawing, preview the path, then start. Keep your hands clear of the moving pen.")
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
                            Button("Start") { model.startJob() }
                                .disabled(!model.isConnected || model.jobText.isEmpty)
                            Button("Pause") { model.pauseJob() }
                                .disabled(!model.isConnected)
                            Button("Resume") { model.resumeJob() }
                                .disabled(!model.isConnected)
                            Button("Cancel") { model.cancelJob() }
                                .disabled(!model.isConnected)
                            Spacer()
                            Text(streamLabel)
                                .font(Theme.captionFont)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: model.streamProgress)
                            .tint(Theme.steelBright)

                        PathPreviewView(job: model.previewJob, workspace: model.machine)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
        case .paused: return "Paused"
        case .completed: return "Done"
        case .cancelled: return "Cancelled"
        case .fault(let m): return "Problem: \(m)"
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.svg]
        if let nc = UTType(filenameExtension: "nc") { types.append(nc) }
        if let gcode = UTType(filenameExtension: "gcode") { types.append(gcode) }
        if let ngc = UTType(filenameExtension: "ngc") { types.append(ngc) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.loadJob(url: url)
        }
    }
}
