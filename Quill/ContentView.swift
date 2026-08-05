import SwiftUI
import CNCCore

enum HobbyistStep: String, CaseIterable, Identifiable {
    case setup = "Setup"
    case move = "Move"
    case calibrate = "Calibrate"
    case draw = "Draw"
    case compose = "Compose"
    case run = "Run"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .setup: return "cable.connector"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .calibrate: return "ruler"
        case .draw: return "pencil.and.outline"
        case .compose: return "doc.richtext"
        case .run: return "play.circle"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    /// Flow order for the hobbyist path (Advanced is unnumbered).
    var stepNumber: Int? {
        switch self {
        case .setup: return 1
        case .move: return 2
        case .calibrate: return 3
        case .draw: return 4
        case .compose: return 5
        case .run: return 6
        case .advanced: return nil
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step: HobbyistStep = .setup

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                brandHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                if let warning = model.motionWarning {
                    HelpCard(
                        title: model.noticeTitle,
                        message: warning,
                        tone: model.noticeTitle == "Emergency stop" || model.noticeTitle == "Machine locked"
                            ? .danger : .caution,
                        actionTitle: (model.isAlarm || model.noticeTitle == "Emergency stop") ? "Unlock" : nil,
                        onAction: (model.isAlarm || model.noticeTitle == "Emergency stop")
                            ? { model.unlock() } : nil,
                        onDismiss: { model.motionWarning = nil }
                    )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let msg = model.penChangeMessage, step == .run || step == .draw {
                    HelpCard(
                        title: "Pen change",
                        message: msg,
                        tone: .caution,
                        onDismiss: { model.penChangeMessage = nil }
                    )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)
                }

                stepPicker
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)

                Group {
                    switch step {
                    case .setup:
                        SetupView { withAnimation(.easeInOut(duration: 0.35)) { step = .move } }
                    case .move:
                        MoveView { withAnimation(.easeInOut(duration: 0.35)) { step = .calibrate } }
                    case .calibrate:
                        CalibrateView { withAnimation(.easeInOut(duration: 0.35)) { step = .draw } }
                    case .draw:
                        DrawView {
                            withAnimation(.easeInOut(duration: 0.35)) { step = .compose }
                        }
                    case .compose:
                        ComposeGlassView {
                            withAnimation(.easeInOut(duration: 0.35)) { step = .run }
                        }
                    case .run:
                        RunGlassView()
                    case .advanced:
                        AdvancedView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.35), value: step)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh") { model.refreshPorts() }
                Button("Status") { model.requestStatus() }
                    .disabled(!model.isConnected)
                Button("Emergency Stop", role: .destructive) { model.halt() }
                    .disabled(!model.isConnected)
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Emergency stop — hold feed, cancel the job, and reset the controller (⌘.)")
            }
        }
        .onAppear { model.refreshPorts() }
        .onOpenURL { url in
            model.loadJob(url: url)
            step = .draw
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .alert("Reset machine settings?", isPresented: $model.confirmFactoryReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset to factory", role: .destructive) { model.performFactoryReset() }
        } message: {
            Text("This restores the controller’s factory numbers. Drawing size and speed may change — run Check machine afterward.")
        }
        .sheet(isPresented: $model.showCalibrationWizard) {
            CalibrationWizardView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 520)
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Theme.brandName)
                    .font(Theme.brandFont)
                    .foregroundStyle(Theme.ink)
                Text(Theme.brandSubtitle)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            EmergencyStopButton(bindsShortcut: true)
            connectionChip
        }
    }

    private var connectionChip: some View {
        let connected = model.isConnected
        let alarm = connected && model.isAlarm
        return HStack(spacing: 8) {
            GlassChip(tint: (alarm ? Theme.danger : (connected ? Theme.ok : Theme.steel)).opacity(0.3)) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connected ? (alarm ? Theme.danger : Theme.ok) : Theme.inkMuted)
                        .frame(width: 8, height: 8)
                    Text(connected ? (alarm ? "Locked" : "Connected") : "Offline")
                        .font(Theme.captionFont.weight(.semibold))
                    if connected {
                        Text(String(format: "%.0f, %.0f", model.status.mpos.x, model.status.mpos.y))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            if alarm {
                Button("Unlock") { model.unlock() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
                    .controlSize(.small)
                    .help("Clear the Alarm lock so the machine can move again")
            }
        }
    }

    private var stepPicker: some View {
        GlassEffectContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HobbyistStep.allCases) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                step = item
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if let n = item.stepNumber {
                                    Text("\(n)")
                                        .font(.system(.caption2, design: .rounded).weight(.bold))
                                        .foregroundStyle(step == item ? Theme.ink : Theme.inkMuted)
                                        .frame(width: 16, height: 16)
                                        .background(
                                            Circle()
                                                .fill(step == item ? Theme.mist : Theme.mist.opacity(0.55))
                                        )
                                }
                                Label(item.rawValue, systemImage: item.symbol)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(step == item ? Theme.ink : Theme.inkMuted)
                        .quillGlass(
                            tint: step == item ? Theme.steelBright.opacity(0.45) : nil,
                            shape: .capsule
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
