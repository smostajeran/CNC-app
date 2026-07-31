import SwiftUI
import CNCCore

enum HobbyistStep: String, CaseIterable, Identifiable {
    case setup = "Setup"
    case move = "Move"
    case calibrate = "Calibrate"
    case draw = "Draw"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .setup: return "cable.connector"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .calibrate: return "ruler"
        case .draw: return "pencil.and.outline"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step: HobbyistStep = .setup
    @Namespace private var glassNamespace

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
                        title: "Check power",
                        message: warning,
                        tone: .caution,
                        onDismiss: { model.motionWarning = nil }
                    )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                stepPicker
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)

                Group {
                    switch step {
                    case .setup:
                        SetupView { withAnimation(.smooth) { step = .move } }
                    case .move:
                        MoveView { withAnimation(.smooth) { step = .calibrate } }
                    case .calibrate:
                        CalibrateView { withAnimation(.smooth) { step = .draw } }
                    case .draw:
                        DrawView()
                    case .advanced:
                        AdvancedView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.smooth(duration: 0.35), value: step)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh") { model.refreshPorts() }
                Button("Status") { model.requestStatus() }
                    .disabled(!model.isConnected)
                Button("Halt", role: .destructive) { model.halt() }
                    .disabled(!model.isConnected)
                    .help("Emergency stop — cancel the job and halt motion")
            }
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
    }

    private var brandHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Theme.brandName)
                    .font(Theme.brandFont)
                    .foregroundStyle(Theme.ink)
                Text(Theme.brandSubtitle)
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            connectionChip
        }
    }

    private var connectionChip: some View {
        let connected = model.isConnected
        return GlassChip(tint: (connected ? Theme.ok : Theme.steel).opacity(0.3)) {
            HStack(spacing: 8) {
                Circle()
                    .fill(connected ? (model.isAlarm ? Theme.danger : Theme.ok) : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(connected ? (model.isAlarm ? "Locked" : "Connected") : "Offline")
                    .font(Theme.captionFont.weight(.semibold))
            }
        }
    }

    private var stepPicker: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                ForEach(HobbyistStep.allCases) { item in
                    Button {
                        withAnimation(.smooth(duration: 0.35)) {
                            step = item
                        }
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(step == item ? Theme.ink : .secondary)
                    .glassEffect(
                        step == item
                            ? Glass.regular.tint(Theme.steelBright.opacity(0.45))
                            : .regular,
                        in: .capsule
                    )
                    .glassEffectID(item.id, in: glassNamespace)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
