import SwiftUI
import CNCCore

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader

                GlassPanel(tint: Theme.steel.opacity(0.15)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Pen plotter (motor lift) · TA-4", systemImage: "pencil.tip.crop.circle")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.steel)
                            .help("Matches Bachin Draw “Pen Writing Machine with Motor” (T-A4). Not servo-pen or laser mode.")

                        Text("1. Plug in the USB cable and the 12V power adapter.\n2. Flip the blue power switch so the board POWER LED is on.\n3. Choose the USB cable below, then Connect.")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker("USB cable", selection: $model.selectedPort) {
                            Text("None found").tag(String?.none)
                            ForEach(model.ports) { port in
                                Text(friendlyPortName(port)).tag(Optional(port.path))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        DisclosureGroup("Speed settings (usually leave alone)") {
                            HStack {
                                Text("Baud rate")
                                    .font(Theme.captionFont)
                                TextField("", value: $model.baudRate, format: .number)
                                    .frame(width: 100)
                            }
                            .padding(.top, 6)
                        }
                        .font(Theme.captionFont)

                        HStack(spacing: 12) {
                            if model.isConnected {
                                Button("Disconnect") { model.disconnect() }
                            } else {
                                Button("Connect") { model.connect() }
                                    .keyboardShortcut(.defaultAction)
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.steel)
                            }
                            Button("Check machine") { model.probe() }
                                .disabled(!model.isConnected)
                            Button("Refresh cables") { model.refreshPorts() }
                        }

                        statusLine
                    }
                }

                if model.portsEmpty {
                    HelpCard(
                        title: "No USB cable found",
                        message: AppModel.emptyPortHelp,
                        tone: .caution
                    )
                }

                if model.isAlarm {
                    HelpCard(
                        title: "Machine is locked (Alarm)",
                        message: "Open Advanced and tap Unlock, then Soft reset if needed. This is common after a power glitch or hitting an end switch. After unlock, use Move → Home X/Y if you want to re-seek the limit switches.",
                        tone: .danger
                    )
                }

                FirmwareFriendlyView(assessment: model.firmwareAssessment)

                if model.isConnected {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Workspace \(Int(model.machine.travelX)) × \(Int(model.machine.travelY)) mm")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text("Pen lift (Bachin motor-pen): up \(fmt(model.machine.penUpZ)) mm · down \(fmt(model.machine.penDownZ)) mm — aim for ≤5 mm gap when raised (Move to adjust).")
                                .font(Theme.captionFont)
                                .foregroundStyle(.secondary)
                            if let build = model.machine.buildInfo, !build.isEmpty {
                                Text(build)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                            Button("Continue to Move") { onContinue() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.steel)
                                .padding(.top, 4)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup")
                .font(Theme.stepTitleFont)
                .foregroundStyle(Theme.ink)
            Text("Get the plotter talking to your Mac. You only need this once each time you plug in.")
                .font(Theme.bodyFont)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let (label, tone): (String, Color) = {
            switch model.connectionState {
            case .disconnected: return ("Not connected", .secondary)
            case .connecting: return ("Connecting…", Theme.steel)
            case .connected:
                if model.isAlarm { return ("Connected · locked (Alarm)", Theme.danger) }
                return ("Connected · \(model.status.state)", Theme.ok)
            case .fault(let msg): return ("Problem: \(msg)", Theme.danger)
            }
        }()
        GlassChip(tint: tone.opacity(0.25)) {
            HStack(spacing: 8) {
                Circle().fill(tone).frame(width: 8, height: 8)
                Text(label)
                    .font(Theme.captionFont.weight(.medium))
            }
        }
    }

    private func friendlyPortName(_ port: SerialPortInfo) -> String {
        let name = port.name
        if name.localizedCaseInsensitiveContains("usb") || name.localizedCaseInsensitiveContains("wch") {
            return "USB plotter · \(name)"
        }
        return name
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}

struct FirmwareFriendlyView: View {
    let assessment: FirmwareAssessment

    var body: some View {
        HelpCard(
            title: title,
            message: bodyMessage,
            tone: tone
        )
    }

    private var title: String {
        switch assessment.verdict {
        case .compatible: return "Firmware looks good (\(assessment.versionLabel))"
        case .caution: return "Firmware needs care (\(assessment.versionLabel))"
        case .incompatibleHint: return "Firmware may not match (\(assessment.versionLabel))"
        case .unknown: return "Firmware not checked yet"
        }
    }

    private var bodyMessage: String {
        var parts = [assessment.summary]
        if !assessment.notes.isEmpty {
            parts.append(assessment.notes.joined(separator: " "))
        }
        switch assessment.verdict {
        case .unknown:
            parts.append("After Connect, tap Check machine.")
        case .compatible:
            parts.append("You’re ready to nudge the pen in Move.")
        case .caution, .incompatibleHint:
            parts.append("You can still try Move carefully; open Advanced if something acts odd.")
        }
        return parts.joined(separator: " ")
    }

    private var tone: HelpTone {
        switch assessment.verdict {
        case .compatible: return .ok
        case .caution: return .caution
        case .incompatibleHint: return .danger
        case .unknown: return .info
        }
    }
}
