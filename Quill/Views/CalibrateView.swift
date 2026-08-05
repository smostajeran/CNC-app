import SwiftUI

private enum CalibratePhase: String, CaseIterable, Identifiable {
    case paper = "Paper size"
    case origin = "Start corner"
    case scale = "Ruler check"

    var id: String { rawValue }
}

struct CalibrateView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: () -> Void

    @State private var phase: CalibratePhase = .paper
    @State private var widthMm: Double = 390
    @State private var heightMm: Double = 200
    @State private var writeLimits = true
    @State private var axis: CalibrationAxis = .x
    @State private var commandedMm: Double = 100
    @State private var measuredMm: Double = 100
    @State private var movedForMeasure = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calibrate")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Match Quill to your paper so drawings land where you expect.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.inkMuted)
                }

                if !model.isConnected {
                    HelpCard(
                        title: "Connect first",
                        message: "Finish Setup, then come back to calibrate the drawing surface.",
                        tone: .caution
                    )
                }

                phasePicker

                if let note = model.calibrationNote {
                    HelpCard(
                        title: "Saved",
                        message: note + (phase == .scale
                            ? " Next: open a drawing in Draw, or continue below."
                            : " Tap Next to continue calibration."),
                        tone: .ok,
                        actionTitle: phase == .scale ? "Continue to Draw" : "Next",
                        onAction: {
                            model.calibrationNote = nil
                            if phase == .scale { onContinue() } else { goNext() }
                        },
                        onDismiss: { model.calibrationNote = nil }
                    )
                }

                switch phase {
                case .paper: paperPanel
                case .origin: originPanel
                case .scale: scalePanel
                }

                HStack {
                    if phase != .paper {
                        Button("Back") { goBack() }
                    }
                    Spacer()
                    if phase != .scale {
                        Button("Next") { goNext() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.steel)
                    } else {
                        HStack(spacing: 10) {
                            Button("Axis scale wizard…") {
                                model.setCalibrationWizardOpen(true)
                            }
                            .disabled(!model.isConnected)
                            Button("Continue to Draw") { onContinue() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.steel)
                        }
                    }
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

    private var phasePicker: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                ForEach(CalibratePhase.allCases) { item in
                    Button {
                        withAnimation(.easeInOut) { phase = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(phase == item ? Theme.ink : Theme.inkMuted)
                    .quillGlass(
                        tint: phase == item ? Theme.steelBright.opacity(0.4) : nil,
                        shape: .capsule
                    )
                }
            }
        }
    }

    private var paperPanel: some View {
        GlassPanel(tint: Theme.steel.opacity(0.1)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("1. Drawing area")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text("How big is the paper (or usable bed) you want to draw on? Quill uses this to fit SVG jobs.")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    presetButton("Full bed", w: 390, h: 200)
                    presetButton("A4 landscape", w: 297, h: 200)
                    presetButton("A5", w: 210, h: 148)
                }

                HStack(spacing: 16) {
                    labeledField("Width mm", value: $widthMm)
                    labeledField("Height mm", value: $heightMm)
                }

                Toggle("Also save as machine soft limits ($130 / $131)", isOn: $writeLimits)
                    .font(Theme.captionFont)

                Text(String(
                    format: "Current in Quill: %.0f × %.0f mm",
                    model.machine.travelX,
                    model.machine.travelY
                ))
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)

                Button("Save paper size") {
                    model.applyPaperSize(
                        widthMm: widthMm,
                        heightMm: heightMm,
                        writeToController: writeLimits
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.steel)
                .disabled(!model.isConnected && writeLimits)
            }
        }
    }

    private var originPanel: some View {
        GlassPanel(tint: Theme.steel.opacity(0.1)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("2. Start corner")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text("Put a pen in, then nudge the carriage so the tip sits over the bottom-left of your paper (the corner where drawing should start).")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)

                Text(String(
                    format: "Position now: X %.1f · Y %.1f · Z %.1f",
                    model.status.mpos.x,
                    model.status.mpos.y,
                    model.status.mpos.z
                ))
                .font(.system(.body, design: .rounded).monospacedDigit())

                Text("Use Move if you need bigger nudges, then come back here.")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)

                Button("This is the start corner") {
                    model.setDrawingOriginHere()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.steel)
                .disabled(!model.isConnected)

                HelpCard(
                    title: "Tip",
                    message: "This sets work zero (G54). Soft reset can clear temporary offsets — run this again if drawings start in the wrong place after a reset.",
                    tone: .info
                )
            }
        }
    }

    private var scalePanel: some View {
        GlassPanel(tint: Theme.steel.opacity(0.1)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("3. Ruler check")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text("Move a known distance, measure with a ruler, and Quill fixes the scale if it’s off.")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)

                Picker("Axis", selection: $axis) {
                    ForEach(CalibrationAxis.allCases) { a in
                        Text(a.label).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.isConnected)

                HStack(spacing: 16) {
                    labeledField("Move mm", value: $commandedMm)
                    labeledField("Measured mm", value: $measuredMm)
                        .disabled(!movedForMeasure)
                }

                HStack(spacing: 10) {
                    Button("Move \(Int(commandedMm)) mm") {
                        model.runCalibrationMove(axis: axis, distanceMm: commandedMm)
                        movedForMeasure = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.steel)
                    .disabled(!model.isConnected || commandedMm < 1)

                    Button("Apply measurement") {
                        model.applyDistanceCalibration(
                            axis: axis,
                            commandedMm: commandedMm,
                            measuredMm: measuredMm
                        )
                    }
                    .disabled(!model.isConnected || !movedForMeasure)

                    Button("Skip") {
                        movedForMeasure = false
                        onContinue()
                    }
                    .buttonStyle(.borderless)
                }

                if let sx = model.machine.stepsPerMmX, let sy = model.machine.stepsPerMmY {
                    Text(String(format: "Steps/mm now: X %.3f · Y %.3f", sx, sy))
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run Check machine on Setup first so Quill knows the current scale.")
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func presetButton(_ title: String, w: Double, h: Double) -> some View {
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
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private func goNext() {
        withAnimation(.easeInOut) {
            switch phase {
            case .paper: phase = .origin
            case .origin: phase = .scale
            case .scale: break
            }
        }
    }

    private func goBack() {
        withAnimation(.easeInOut) {
            switch phase {
            case .paper: break
            case .origin: phase = .paper
            case .scale: phase = .origin
            }
        }
    }
}
