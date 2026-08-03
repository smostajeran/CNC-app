import SwiftUI
import CNCCore

/// Run mode: job, preflight, Frame, Hold/Resume/Stop — Liquid Glass chrome.
struct RunGlassView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Run")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Preflight, frame the page with the pen raised, then plot. Keep clear of the moving carriage.")
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

            HStack(alignment: .top, spacing: 16) {
                GlassPanel(tint: Theme.steel.opacity(0.1), padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(streamLabel)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        ProgressView(value: model.streamProgress)
                            .tint(Theme.steelBright)

                        if let report = model.preflightReport {
                            Text("ETA \(report.estimatedRuntimeLabel) · \(report.parse.penChangeCount) pen change(s)")
                                .font(Theme.captionFont)
                                .foregroundStyle(.secondary)
                            ForEach(report.issues.prefix(5)) { issue in
                                Text("• \(issue.message)")
                                    .font(.caption2)
                                    .foregroundStyle(
                                        issue.severity == .error ? Theme.danger
                                            : (issue.severity == .warning ? Theme.caution : .secondary)
                                    )
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Preflight") { model.runPreflight() }
                                .disabled(model.jobText.isEmpty)
                            Button("Frame") { model.framePage() }
                                .disabled(!model.isConnected || model.composedPage == nil && model.jobText.isEmpty || !model.allowsManualCommands)
                            Button("Start") { model.startJob() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.steel)
                                .disabled(!model.isConnected || model.jobText.isEmpty)
                            Button("Hold") { model.pauseJob() }
                            Button("Resume") { model.resumeJob() }
                            Button("Stop", role: .destructive) { model.cancelJob() }
                        }

                        Text(String(
                            format: "Head %.2f, %.2f, %.2f",
                            model.status.mpos.x, model.status.mpos.y, model.status.mpos.z
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                        if !model.batch.pages.isEmpty {
                            Divider()
                            Text("Batch · \(model.batch.remainingCount) remaining")
                                .font(Theme.captionFont.weight(.semibold))
                            Button("Queue next page") { model.queueNextBatchPage() }
                                .disabled(!model.allowsManualCommands)
                        }
                    }
                }
                .frame(width: 360)

                PathPreviewView(job: model.previewJob, workspace: model.machine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .quillGlass(shape: .rect(cornerRadius: 18))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private var streamLabel: String {
        switch model.streamState {
        case .idle: return "Ready — run Preflight, then Start"
        case .running: return String(format: "Streaming %.0f%% (acked)", model.streamProgress * 100)
        case .paused: return "Hold"
        case .waitingForPenChange: return "Waiting for pen change — Resume after swap"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .fault(let m): return "Fault: \(m)"
        }
    }
}
