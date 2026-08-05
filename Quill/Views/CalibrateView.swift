import SwiftUI
import CNCCore

struct CalibrateView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: () -> Void

    @State private var showQuickAdjust = false
    @State private var widthMm: Double = 390
    @State private var heightMm: Double = 200
    @State private var writeLimits = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calibrate")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Run the controlled wizard so power, direction, end stops, homing, travel, and pen height are proven before you draw.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.inkMuted)
                }

                if !model.isConnected {
                    HelpCard(
                        title: "Connect first",
                        message: "Finish Setup, confirm 12 V power, then start the calibration wizard.",
                        tone: .caution
                    )
                } else if !model.motorsPowerConfirmed {
                    HelpCard(
                        title: "Confirm motor power",
                        message: "USB can show Connected without powering the motors. The wizard blocks motion steps until you confirm regulated 12 V and the POWER LED.",
                        tone: .caution
                    )
                }

                GlassPanel(tint: Theme.steel.opacity(0.12)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Controlled calibration wizard", systemImage: "list.number")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("Power → pen head → direction → end stops → homing → safe travel → limits → pen → accuracy → boundary/oversize → save profile.")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.inkMuted)
                        if model.machine.commissioningComplete {
                            Text("A completed profile is already saved on this Mac — re-run the wizard after hardware changes.")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.ok)
                        }
                        Button("Start calibration wizard…") {
                            model.setCalibrationWizardOpen(true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.steel)
                        .disabled(!model.isConnected)
                    }
                }

                if let note = model.calibrationNote {
                    HelpCard(
                        title: "Saved",
                        message: note,
                        tone: .ok,
                        actionTitle: "Continue to Draw",
                        onAction: {
                            model.calibrationNote = nil
                            onContinue()
                        },
                        onDismiss: { model.calibrationNote = nil }
                    )
                }

                DisclosureGroup("Quick paper size (optional)", isExpanded: $showQuickAdjust) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("For a full re-commission, use the wizard. These presets only adjust Quill’s drawing area (and optionally $130/$131).")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(.top, 8)
                        HStack(spacing: 10) {
                            quickPreset("Full bed", w: 390, h: 200)
                            quickPreset("A4 landscape", w: 297, h: 200)
                            quickPreset(
                                "Conservative",
                                w: MachineProfile.conservativeTravelX,
                                h: MachineProfile.conservativeTravelY
                            )
                        }
                        HStack(spacing: 16) {
                            labeledField("Width mm", value: $widthMm)
                            labeledField("Height mm", value: $heightMm)
                        }
                        Toggle("Also write soft-limit max travel ($130 / $131)", isOn: $writeLimits)
                            .font(Theme.captionFont)
                        Button("Save paper size") {
                            model.applyPaperSize(
                                widthMm: widthMm,
                                heightMm: heightMm,
                                writeToController: writeLimits
                            )
                        }
                        .disabled(!model.isConnected && writeLimits)
                    }
                }
                .font(Theme.captionFont)

                HStack {
                    Spacer()
                    Button("Continue to Draw") { onContinue() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.steel)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            widthMm = model.machine.travelX
            heightMm = model.machine.travelY
        }
    }

    private func quickPreset(_ title: String, w: Double, h: Double) -> some View {
        Button(title) {
            widthMm = w
            heightMm = h
        }
        .buttonStyle(.bordered)
    }

    private func labeledField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.inkMuted)
            TextField("", value: value, format: .number)
                .frame(width: 100)
        }
    }
}
