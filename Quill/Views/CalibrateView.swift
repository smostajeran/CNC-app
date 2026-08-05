import SwiftUI
import CNCCore

struct CalibrateView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: () -> Void

    @State private var writeTravel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calibrate")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Set your paper for Compose, then run the wizard only when you need to commission motors, switches, and travel.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.inkMuted)
                }

                if !model.isConnected {
                    HelpCard(
                        title: "Connect first",
                        message: "Finish Setup, confirm 12 V power, then choose paper or open the wizard.",
                        tone: .caution
                    )
                } else if model.isAlarm {
                    HelpCard(
                        title: "Machine locked",
                        message: "Unlock before jogging or homing. Soft limits ($20) or a failed Home often cause this — E-Stop, Unlock, then continue carefully.",
                        tone: .danger,
                        actionTitle: "Unlock",
                        onAction: { model.unlock() }
                    )
                } else if !model.motorsPowerConfirmed {
                    HelpCard(
                        title: "Confirm motor power",
                        message: "USB can show Connected without powering the motors. Confirm 12 V before any motion in the wizard.",
                        tone: .caution,
                        actionTitle: "Motors powered",
                        onAction: { model.confirmMotorsPowered(true) }
                    )
                }

                // --- Paper (primary) ---
                GlassPanel(tint: Theme.steel.opacity(0.12)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Paper size (Compose)", systemImage: "doc.plaintext")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("TA-4 bed is about 390×200 mm. Full ISO A4 landscape (297×210) is taller than the bed — use A4 landscape (297×200) below.")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.inkMuted)

                        Text("Current: \(model.page.format.name) · \(Int(model.page.format.widthMm))×\(Int(model.page.format.heightMm)) mm")
                            .font(Theme.captionFont.weight(.semibold))
                            .foregroundStyle(Theme.ink)

                        HStack(spacing: 10) {
                            paperButton(PageFormat.a4OnTA4Bed)
                            paperButton(PageFormat.a5Landscape)
                            paperButton(PageFormat.fullBed)
                        }

                        Toggle("Also write max travel $130/$131 (does not turn on soft limits)", isOn: $writeTravel)
                            .font(Theme.captionFont)

                        if !model.pageFitsBed {
                            HelpCard(
                                title: "Page does not fit bed",
                                message: model.pageFitBlockingMessage
                                    ?? "Choose A4 landscape (297×200) or A5 landscape.",
                                tone: .caution,
                                actionTitle: "Use A4 landscape",
                                onAction: { applyA4() }
                            )
                        }
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

                // --- Wizard (secondary, motion-heavy) ---
                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Machine commissioning wizard", systemImage: "list.number")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("Use only when commissioning: direction, end stops, homing, safe travel. Keep E-Stop ready. Do not enable soft limits ($20) until Home seeks the switches correctly.")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.inkMuted)
                        Button("Start calibration wizard…") {
                            model.setCalibrationWizardOpen(true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.steel)
                        .disabled(!model.isConnected)
                    }
                }

                HStack {
                    Spacer()
                    Button("Continue to Compose / Draw") { onContinue() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.steel)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func paperButton(_ format: PageFormat) -> some View {
        let selected = model.page.format.id == format.id
        return Button(format.name) {
            model.applyPageFormatPreset(format, writeTravelToController: writeTravel)
        }
        .buttonStyle(.borderedProminent)
        .tint(selected ? Theme.ok : Theme.steel)
        .disabled(!format.fits(on: model.machine) && format.id != PageFormat.a4OnTA4Bed.id)
        .help("\(Int(format.widthMm))×\(Int(format.heightMm)) mm")
    }

    private func applyA4() {
        model.applyPageFormatPreset(.a4OnTA4Bed, writeTravelToController: writeTravel)
    }
}
