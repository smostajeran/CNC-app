import SwiftUI
import CNCCore

/// Guided wizard: blank paper → mark two points per axis → measure → adjust steps/mm.
struct CalibrationWizardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: WizardStep = .intro
    @State private var axis: CalibrationAxis = .x
    @State private var commandedMm: Double = 100
    @State private var measuredText: String = ""
    @State private var markedStart = false
    @State private var moved = false
    @State private var markedEnd = false
    @State private var xDone = false
    @State private var yDone = false

    private enum WizardStep: Int, CaseIterable {
        case intro
        case prepare
        case markStart
        case move
        case markEnd
        case measure
        case apply
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                paperPreview
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                stepPanel
                    .frame(width: 360)
                    .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if model.machine.stepsPerMmX == nil || model.machine.stepsPerMmY == nil {
                // Encourage probe so we start from firmware values.
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Axis scale wizard")
                    .font(.title2.weight(.semibold))
                Text("Goal: when Quill moves 10 mm, the pen travels 10 mm on paper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var paperPreview: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)

            // Soft page edge
            Rectangle()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)

            GeometryReader { geo in
                let inset: CGFloat = 36
                let w = geo.size.width - inset * 2
                let h = geo.size.height - inset * 2
                let origin = CGPoint(x: inset, y: geo.size.height - inset)

                // Axis guides (light)
                Path { p in
                    p.move(to: origin)
                    p.addLine(to: CGPoint(x: origin.x + w * 0.85, y: origin.y))
                    p.move(to: origin)
                    p.addLine(to: CGPoint(x: origin.x, y: origin.y - h * 0.85))
                }
                .stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Text("X →")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: origin.x + w * 0.42, y: origin.y + 14)
                Text("Y ↑")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: origin.x - 14, y: origin.y - h * 0.42)

                let frac = min(max(commandedMm / max(model.machine.travelX, model.machine.travelY), 0.08), 0.7)
                let end: CGPoint = {
                    switch axis {
                    case .x: return CGPoint(x: origin.x + w * frac, y: origin.y)
                    case .y: return CGPoint(x: origin.x, y: origin.y - h * frac)
                    }
                }()

                if markedStart || step.rawValue >= WizardStep.markStart.rawValue {
                    circle(at: origin, filled: markedStart, label: "1")
                }
                if moved || markedEnd {
                    Path { p in
                        p.move(to: origin)
                        p.addLine(to: end)
                    }
                    .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                if markedEnd || (step.rawValue >= WizardStep.markEnd.rawValue && moved) {
                    circle(at: end, filled: markedEnd, label: "2")
                }

                if markedStart && markedEnd {
                    let mid = CGPoint(x: (origin.x + end.x) / 2, y: (origin.y + end.y) / 2 - 12)
                    Text(String(format: "commanded %.0f mm", commandedMm))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .position(mid)
                }
            }
            .padding(24)

            if step == .intro || step == .prepare {
                VStack(spacing: 8) {
                    Text("Blank page")
                        .font(.title3.weight(.medium))
                    Text("Put a clean white sheet under the pen.\nYou will mark two points, then measure between them.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.white.opacity(0.92))
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func circle(at point: CGPoint, filled: Bool, label: String) -> some View {
        ZStack {
            Circle()
                .fill(filled ? Color.red.opacity(0.85) : Color.red.opacity(0.25))
                .frame(width: 14, height: 14)
            Circle()
                .stroke(Color.red, lineWidth: 1.5)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .position(point)
    }

    @ViewBuilder
    private var stepPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            progressRow

            if !model.isConnected {
                Label("Connect the plotter first (sidebar → Connect).", systemImage: "cable.connector")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let note = model.calibrationNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Group {
                switch step {
                case .intro: introCopy
                case .prepare: prepareCopy
                case .markStart: markStartCopy
                case .move: moveCopy
                case .markEnd: markEndCopy
                case .measure: measureCopy
                case .apply: applyCopy
                case .done: doneCopy
                }
            }

            Spacer(minLength: 0)
            navButtons
        }
    }

    private var progressRow: some View {
        HStack(spacing: 6) {
            ForEach(WizardStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
    }

    private var introCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why calibrate?")
                .font(.headline)
            Text("Quill tells the controller “move 10 mm.” The controller converts that using steps per millimeter ($100 / $101). If those values are wrong, a 10 mm command draws a different length on paper.")
                .font(.callout)
            Text("This wizard draws two marks on each axis. You measure the real distance with a ruler; Quill adjusts the controller so commanded distance matches measured distance.")
                .font(.callout)
            Text("Tip: a longer span (50–100 mm) is more accurate than 10 mm, but the goal is the same — 1 mm commanded = 1 mm on paper.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var prepareCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prepare")
                .font(.headline)
            Text("1. Place a blank white sheet on the bed.\n2. Put a pen in the holder.\n3. Jog so the tip is over the bottom-left of the page.\n4. Optionally Probe $$/$I so Quill reads current steps/mm.")
                .font(.callout)
            HStack {
                Button("Probe $$/$I") { model.probe() }
                    .disabled(!model.isConnected)
                Button("Set Zero here") { model.setWorkZero() }
                    .disabled(!model.isConnected)
            }
            stepsReadout
            Picker("Start with axis", selection: $axis) {
                ForEach(CalibrationAxis.allCases) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)
            .disabled(xDone && !yDone) // if X done, force Y next via done flow
        }
    }

    private var markStartCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mark point 1 — \(axis.label)")
                .font(.headline)
            Text("Lower the pen briefly to leave a small dot on the blank page. This is the start of your \(axis.prompt) measurement.")
                .font(.callout)
            Button("Mark point 1") {
                model.markCalibrationPoint()
                markedStart = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.isConnected)
            if markedStart {
                Text("Point 1 marked. Next, move a known distance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var moveCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move \(axis.shortLabel)")
                .font(.headline)
            Text("Quill will jog a commanded distance \(axis.prompt). Pick a distance you can measure cleanly with a ruler.")
                .font(.callout)
            Picker("Commanded mm", selection: $commandedMm) {
                Text("10 mm").tag(10.0)
                Text("50 mm").tag(50.0)
                Text("100 mm").tag(100.0)
            }
            .pickerStyle(.segmented)
            Button("Move \(Int(commandedMm)) mm on \(axis.shortLabel)") {
                model.runCalibrationMove(axis: axis, distanceMm: commandedMm)
                moved = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.isConnected || !markedStart)
            if moved {
                Text("Carriage moved. Mark point 2 at the new tip position.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var markEndCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mark point 2 — \(axis.label)")
                .font(.headline)
            Text("Leave a second dot where the pen tip is now. You will measure between point 1 and point 2.")
                .font(.callout)
            Button("Mark point 2") {
                model.markCalibrationPoint()
                markedEnd = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.isConnected || !moved)
            if markedEnd {
                Text("Both marks are on the page. Grab a ruler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var measureCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Measure")
                .font(.headline)
            Text("With a ruler, measure the distance between the two marks in millimeters. Enter what you actually see — not the commanded value.")
                .font(.callout)
            HStack {
                Text("Measured mm")
                TextField("e.g. 98.5", text: $measuredText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            Text(String(format: "Commanded: %.0f mm  ·  Ideal: measured ≈ %.0f mm", commandedMm, commandedMm))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var applyCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apply adjustment")
                .font(.headline)
            let measured = Double(measuredText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let current = axis == .x
                ? (model.machine.stepsPerMmX ?? MachineProfile.defaultStepsPerMm)
                : (model.machine.stepsPerMmY ?? MachineProfile.defaultStepsPerMm)
            let preview = MachineProfile.correctedStepsPerMm(
                current: current,
                commandedMm: commandedMm,
                measuredMm: measured
            )

            Text(String(
                format: "Commanded %.0f mm · measured %.1f mm",
                commandedMm, measured
            ))
            .font(.callout)

            if let preview {
                Text(String(format: "New \(axis.shortLabel) steps/mm: %.4f  (was %.4f)", preview, current))
                    .font(.system(.body, design: .monospaced))
                if abs(measured - commandedMm) < 0.3 {
                    Text("Already very close — applying will make a tiny tweak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if measured < commandedMm {
                    Text("Machine moved short → increasing steps/mm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Machine moved long → decreasing steps/mm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Enter a valid measured length first.")
                    .foregroundStyle(.orange)
            }

            Button("Write \(axis.shortLabel) calibration to controller") {
                model.applyDistanceCalibration(
                    axis: axis,
                    commandedMm: commandedMm,
                    measuredMm: measured
                )
                switch axis {
                case .x: xDone = true
                case .y: yDone = true
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.isConnected || preview == nil)
        }
    }

    private var doneCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(xDone && yDone ? "Calibration complete" : "Axis saved")
                .font(.headline)
            stepsReadout
            if xDone && !yDone {
                Text("X is updated. Next, calibrate Y the same way: two marks, measure, apply.")
                    .font(.callout)
            } else if yDone && !xDone {
                Text("Y is updated. You can still run X if needed.")
                    .font(.callout)
            } else {
                Text("Both axes are adjusted. Draw a 10×10 mm square or a 100 mm line and verify with a ruler.")
                    .font(.callout)
            }
        }
    }

    private var stepsReadout: some View {
        Group {
            if let sx = model.machine.stepsPerMmX, let sy = model.machine.stepsPerMmY {
                Text(String(format: "Steps/mm: X %.3f · Y %.3f", sx, sy))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("Steps/mm unknown — run Probe $$/$I for best results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navButtons: some View {
        HStack {
            if step != .intro {
                Button("Back") { goBack() }
            }
            Spacer()
            if step == .done {
                if !(xDone && yDone) {
                    Button(xDone ? "Calibrate Y" : "Calibrate X") {
                        axis = xDone ? .y : .x
                        resetAxisState()
                        step = .markStart
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Finish") {
                    model.showCalibrationWizard = false
                    dismiss()
                }
            } else {
                Button(primaryLabel) { goNext() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var primaryLabel: String {
        switch step {
        case .apply: return "Continue"
        case .intro: return "Start"
        default: return "Next"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .intro: return true
        case .prepare: return model.isConnected
        case .markStart: return markedStart
        case .move: return moved
        case .markEnd: return markedEnd
        case .measure:
            let v = Double(measuredText.replacingOccurrences(of: ",", with: ".")) ?? 0
            return v > 0.1
        case .apply: return true
        case .done: return true
        }
    }

    private func goNext() {
        model.calibrationNote = nil
        switch step {
        case .intro: step = .prepare
        case .prepare:
            resetAxisState()
            step = .markStart
        case .markStart: step = .move
        case .move: step = .markEnd
        case .markEnd: step = .measure
        case .measure: step = .apply
        case .apply: step = .done
        case .done: break
        }
    }

    private func goBack() {
        model.calibrationNote = nil
        switch step {
        case .intro: break
        case .prepare: step = .intro
        case .markStart: step = .prepare
        case .move: step = .markStart
        case .markEnd: step = .move
        case .measure: step = .markEnd
        case .apply: step = .measure
        case .done: step = .apply
        }
    }

    private func resetAxisState() {
        markedStart = false
        moved = false
        markedEnd = false
        measuredText = ""
        model.calibrationNote = nil
    }
}