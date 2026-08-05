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
                        .foregroundStyle(.secondary)
                }

                if !model.isConnected {
                    HelpCard(
                        title: "Connect first",
                        message: "Go back to Setup, choose the USB cable, and tap Connect.",
                        tone: .caution
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
                                .disabled(!model.isConnected || !model.allowsManualCommands)
                                .help("Drive X and Y to the physical end switches ($H). Clear the bed first.")
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
                            }
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Position")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                Text(positionLabel)
                                    .font(.system(.title3, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Theme.ink)
                                Text("If nothing moves, check the 12V adapter and blue power switch — USB can connect while motors are off.")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(.secondary)
                                Text("Home X/Y seeks the two end buttons so the controller knows the corner of the bed. After homing, jog to your page corner and set zero in Calibrate.")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(.secondary)
                                DisclosureGroup("Pen heights (mm)") {
                                    HStack {
                                        Text("Up")
                                        TextField("", value: $model.machine.penUpZ, format: .number)
                                            .frame(width: 56)
                                        Text("Down")
                                        TextField("", value: $model.machine.penDownZ, format: .number)
                                            .frame(width: 56)
                                    }
                                    .font(Theme.captionFont)
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
            jogButton("↑", help: "Move away from you") {
                model.jog(dx: 0, dy: model.jogStep)
            }
            HStack(spacing: 10) {
                jogButton("←", help: "Move left") {
                    model.jog(dx: -model.jogStep, dy: 0)
                }
                jogButton("→", help: "Move right") {
                    model.jog(dx: model.jogStep, dy: 0)
                }
            }
            jogButton("↓", help: "Move toward you") {
                model.jog(dx: 0, dy: -model.jogStep)
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

    private var positionLabel: String {
        String(
            format: "X %.1f · Y %.1f · Z %.1f",
            model.status.mpos.x,
            model.status.mpos.y,
            model.status.mpos.z
        )
    }
}
