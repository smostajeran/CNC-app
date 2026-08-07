import SwiftUI

struct MoveView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: () -> Void
    @State private var confirmHomeXY = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Move")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Nudge the pen a little so you know power and direction are right before drawing.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.inkMuted)
                }

                if !model.isConnected {
                    HelpCard(
                        title: "Connect first",
                        message: "Go back to Setup, choose the USB cable, and tap Connect.",
                        tone: .caution
                    )
                } else if model.isAlarm {
                    HelpCard(
                        title: "Machine is locked",
                        message: "Unlock before jogging or Home X/Y. Soft reset in Advanced if Unlock alone does not clear it.",
                        tone: .danger,
                        actionTitle: "Unlock",
                        onAction: { model.unlock() }
                    )
                } else if !model.motorsPowerConfirmed {
                    HelpCard(
                        title: "Confirm 12 V motor power",
                        message: "USB can show Connected while motors are unpowered. Confirm the adapter and POWER LED before Home X/Y — missed steps spoil calibration.",
                        tone: .caution,
                        actionTitle: "Motors powered",
                        onAction: { model.confirmMotorsPowered(true) }
                    )
                }

                GlassEffectContainer {
                    HStack(alignment: .top, spacing: 16) {
                        GlassPanel(tint: Theme.steel.opacity(0.12), padding: 24) {
                            VStack(spacing: 16) {
                                Text("Step size")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Picker("Step", selection: $model.jogStep) {
                                    Text("1 mm").tag(1.0)
                                    Text("5 mm").tag(5.0)
                                    Text("10 mm").tag(10.0)
                                    Text("50 mm").tag(50.0)
                                }
                                .pickerStyle(.segmented)
                                .disabled(!model.isConnected)

                                jogPad
                                    .padding(.vertical, 8)

                                Button {
                                    confirmHomeXY = true
                                } label: {
                                    Label("Home X/Y", systemImage: "house")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.isConnected || !model.allowsManualCommands || !model.motorsPowerConfirmed)
                                .help("Drive X and Y to the physical end switches ($H). Confirm 12 V power first. Clear the bed.")
                                .confirmationDialog(
                                    "Home X and Y to the end switches?",
                                    isPresented: $confirmHomeXY,
                                    titleVisibility: .visible
                                ) {
                                    Button("Home X/Y") { model.homeXY() }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("The gantry will move until both end buttons click. Keep hands clear and remove anything that could snag the rails.")
                                }

                                Button {
                                    model.setPaperCornerHere()
                                } label: {
                                    Label("Paper corner is here", systemImage: "doc.plaintext")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.steel)
                                .disabled(!model.isConnected || !model.xyHomedThisSession || !model.allowsManualCommands)
                                .help("Sets Compose page origin to this bed position. Does not change G54 — that stays at Home so jobs cannot run past the bed.")

                                Button {
                                    model.setWorkZero()
                                } label: {
                                    Label("Sync work zero here", systemImage: "scope")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.isConnected || !model.allowsManualCommands)
                                .help("G10 L20 — only at the homed switch corner for Compose. For paper placement use “Paper corner is here”.")

                                HStack(spacing: 12) {
                                    Button {
                                        model.penUp()
                                    } label: {
                                        Label("Pen up", systemImage: "arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    Button {
                                        model.penDown()
                                    } label: {
                                        Label("Pen down", systemImage: "arrow.down")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.steel)
                                }
                                .disabled(!model.isConnected)

                                EmergencyStopButton(compact: true)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Position")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                Text(machinePositionLabel)
                                    .font(.system(.title3, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Theme.ink)
                                Text(workPositionLabel)
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Theme.inkMuted)
                                Text(paperOriginLabel)
                                    .font(Theme.captionFont.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("If nothing moves, check the 12V adapter and blue power switch — USB can connect while motors are off.")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(Theme.inkMuted)
                                Text("1) Home X/Y (auto-syncs work zero). 2) Jog to the paper’s bottom-left. 3) Paper corner is here. Soft limits ($20) after a good Home — before Start.")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(Theme.inkMuted)
                                DisclosureGroup("Pen heights (mm)") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Bachin motor-pen guide (T-A4): up gap ≤ 5 mm above paper; down lightly on the page. Quill uses GRBL Z — higher lifts the pen (typical up 5, down 0). Range 0–8.")
                                            .font(Theme.captionFont)
                                            .foregroundStyle(Theme.inkMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack {
                                            Text("Up")
                                            TextField("", value: $model.machine.penUpZ, format: .number)
                                                .frame(width: 56)
                                                .onSubmit { model.clampPenHeightsToBachinRange() }
                                            Text("Down")
                                            TextField("", value: $model.machine.penDownZ, format: .number)
                                                .frame(width: 56)
                                                .onSubmit { model.clampPenHeightsToBachinRange() }
                                        }
                                        .font(Theme.captionFont)
                                        Button("Use recommended (up 5 · down 0)") {
                                            model.applyRecommendedPenHeights()
                                        }
                                        .font(Theme.captionFont)
                                    }
                                    .padding(.top, 6)
                                }
                                .font(Theme.captionFont)
                                Button("Continue to Calibrate") { onContinue() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.steel)
                                    .disabled(!model.isConnected)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(minWidth: 220, idealWidth: 260)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var jogPad: some View {
        VStack(spacing: 10) {
            Text("Pad matches the Run/Compose preview: ↑ = +Y (top of page), → = +X (right).")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
            jogButton("↑ +Y", help: "+Y — toward the top of the page preview") {
                model.jog(dx: 0, dy: model.jogStep)
            }
            HStack(spacing: 10) {
                jogButton("← −X", help: "−X — toward the left of the page preview") {
                    model.jog(dx: -model.jogStep, dy: 0)
                }
                jogButton("→ +X", help: "+X — toward the right of the page preview") {
                    model.jog(dx: model.jogStep, dy: 0)
                }
            }
            jogButton("↓ −Y", help: "−Y — toward the bottom of the page preview") {
                model.jog(dx: 0, dy: -model.jogStep)
            }
            if model.machine.invertX || model.machine.invertY {
                Text("Axis flip ($3) is on — toggle Flip in Advanced if the head moves opposite the pad.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.caution)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(!model.isConnected)
    }

    private func jogButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .frame(width: 72, height: 56)
        }
        .buttonStyle(.bordered)
        .help(help)
        .quillGlass(tint: Theme.steelBright.opacity(0.2), shape: .rect(cornerRadius: 14), interactive: true)
    }

    private var machinePositionLabel: String {
        String(
            format: "Machine  X %.1f · Y %.1f · Z %.1f",
            model.status.mpos.x,
            model.status.mpos.y,
            model.status.mpos.z
        )
    }

    private var workPositionLabel: String {
        String(
            format: "Work     X %.1f · Y %.1f · Z %.1f",
            model.status.wpos.x,
            model.status.wpos.y,
            model.status.wpos.z
        )
    }

    private var paperOriginLabel: String {
        String(
            format: "Paper origin on bed  X %.1f · Y %.1f mm",
            model.page.bedOriginX,
            model.page.bedOriginY
        )
    }
}
