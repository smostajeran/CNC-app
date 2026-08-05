import SwiftUI
import CNCCore

/// Run mode: job, preflight, Frame, Hold/Resume/Stop — Liquid Glass chrome.
struct RunGlassView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmStart = false

    private var hasJob: Bool { !model.jobText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Run")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Preflight, frame the page with the pen raised, then plot. Keep clear of the moving carriage.")
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
                    message: "Finish Setup before framing or starting a job.",
                    tone: .caution
                )
                .padding(.horizontal, 28)
            } else if model.isAlarm {
                HelpCard(
                    title: "Machine is locked",
                    message: model.isUnlocking
                        ? "Clearing Alarm…"
                        : "ALARM:3 usually means Emergency Stop or Soft reset during motion. Tap Unlock ($X) — do not Soft reset again first. Then Home X/Y before Start.",
                    tone: .danger,
                    actionTitle: model.isUnlocking ? nil : "Unlock",
                    onAction: model.isUnlocking ? nil : { model.unlock() }
                )
                .padding(.horizontal, 28)
            } else if !model.xyHomedThisSession {
                HelpCard(
                    title: "Home required before Start",
                    message: "Start is blocked until Move → Home X/Y finishes at Idle. Without a trusted origin the gantry can run off the open end of the bed.",
                    tone: .danger
                )
                .padding(.horizontal, 28)
            } else if !model.machine.softLimitsEnabled {
                HelpCard(
                    title: "Soft limits required before Start",
                    message: "Enable soft limits ($20) in Calibrate after Homing so travel cannot exceed $130/$131.",
                    tone: .danger
                )
                .padding(.horizontal, 28)
            }

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
                                .foregroundStyle(Theme.inkMuted)
                            ForEach(report.issues.prefix(5)) { issue in
                                Text("• \(issue.message)")
                                    .font(.caption2)
                                    .foregroundStyle(
                                        issue.severity == .error ? Theme.danger
                                            : (issue.severity == .warning ? Theme.caution : Theme.inkMuted)
                                    )
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Preflight") { model.runPreflight() }
                                .disabled(!hasJob)
                            Button("Frame") { model.framePage() }
                                .disabled(
                                    !model.isConnected
                                        || (!hasJob && model.composedPage == nil)
                                        || !model.allowsManualCommands
                                )
                            Button("Start") { confirmStart = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.steel)
                                .disabled(!model.isConnected || !hasJob)
                            Button("Hold") { model.pauseJob() }
                            Button("Resume") { model.resumeJob() }
                            Button("Stop", role: .destructive) { model.cancelJob() }
                                .help("Cancel the job stream without resetting the controller")
                        }

                        EmergencyStopButton()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(
                            format: "Head %.2f, %.2f, %.2f",
                            model.status.mpos.x, model.status.mpos.y, model.status.mpos.z
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.inkMuted)

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

                Group {
                    if hasJob {
                        PathPreviewView(job: model.previewJob, workspace: model.machine)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 36, weight: .light, design: .rounded))
                                .foregroundStyle(Theme.steel)
                            Text("Nothing to run")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Compose a page or open a drawing in Draw, then return here to preflight and plot.")
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.inkMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(28)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .quillGlass(shape: .rect(cornerRadius: 18))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .confirmationDialog(
            "Start plotting now?",
            isPresented: $confirmStart,
            titleVisibility: .visible
        ) {
            Button("Start job") { model.startJob() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Preflight runs first. Keep hands clear of the carriage and rails.")
        }
    }

    private var streamLabel: String {
        switch model.streamState {
        case .idle: return hasJob ? "Ready — run Preflight, then Start" : "Load a job from Draw or Compose"
        case .running: return String(format: "Streaming %.0f%% (acked)", model.streamProgress * 100)
        case .paused: return "Hold"
        case .waitingForPenChange: return "Waiting for pen change — Resume after swap"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .fault(let m): return "Fault: \(m)"
        }
    }
}
