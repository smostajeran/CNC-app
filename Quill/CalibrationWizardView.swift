import SwiftUI
import CNCCore

/// Controlled commissioning wizard — power-gated; no motion calibration without 12 V confirmed.
struct CalibrationWizardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .power
    @State private var power12V = false
    @State private var powerLED = false
    @State private var xDirectionOK = false
    @State private var yDirectionOK = false
    @State private var xSwitchSawOff = false
    @State private var xSwitchSawOn = false
    @State private var ySwitchSawOff = false
    @State private var ySwitchSawOn = false
    @State private var endStopBlocked = false
    @State private var travelX: Double = MachineProfile.conservativeTravelX
    @State private var travelY: Double = MachineProfile.conservativeTravelY
    @State private var measuringAxis: CalibrationAxis = .x
    @State private var travelStep: Double = 10
    @State private var enableHardLimits = false
    @State private var measuredX: String = "100"
    @State private var measuredY: String = "100"
    @State private var scaleApplied = false
    @State private var oversizeRejected = false
    @State private var boundaryReady = false
    @State private var homingStarted = false

    private enum Step: Int, CaseIterable, Identifiable {
        case power, head, direction, endStops, homing, travel, limits, pen, accuracy, safety, save

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .power: return "Power check"
            case .head: return "Pen head"
            case .direction: return "Direction test"
            case .endStops: return "End-stop test"
            case .homing: return "Homing test"
            case .travel: return "Safe travel"
            case .limits: return "Enable limits"
            case .pen: return "Pen calibrate"
            case .accuracy: return "Accuracy test"
            case .safety: return "Safety test"
            case .save: return "Save profile"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                progressRail
                    .frame(width: 200)
                Divider()
                ScrollView {
                    stepBody
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            travelX = min(model.machine.travelX, MachineProfile.conservativeTravelX)
            travelY = min(model.machine.travelY, MachineProfile.conservativeTravelY)
            if travelX < 20 { travelX = MachineProfile.conservativeTravelX }
            if travelY < 20 { travelY = MachineProfile.conservativeTravelY }
            model.requestStatus()
        }
        .onChange(of: model.status.pins) { pins in
            guard step == .endStops, !endStopBlocked else { return }
            if !pins.x { xSwitchSawOff = true }
            if pins.x { xSwitchSawOn = true }
            if !pins.y { ySwitchSawOff = true }
            if pins.y { ySwitchSawOn = true }
            // Stuck active at step entry is handled when entering endStops.
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calibration wizard")
                    .font(.title2.weight(.semibold))
                Text("Controlled commissioning — motion steps stay blocked until 12 V power is confirmed.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            EmergencyStopButton(compact: true)
            Button("Close") {
                model.setCalibrationWizardOpen(false)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Step.allCases) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.rawValue <= step.rawValue ? Theme.steel : Theme.mist)
                        .frame(width: 8, height: 8)
                    Text(item.title)
                        .font(.system(.caption, design: .rounded).weight(item == step ? .semibold : .regular))
                        .foregroundStyle(item == step ? Theme.ink : Theme.inkMuted)
                }
            }
            Spacer()
            if !model.motorsPowerConfirmed {
                Text("Motors power not confirmed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !canContinue, let hint = continueBlockedHint {
                Text(hint)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.caution)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                Button("Back") { goBack() }
                    .disabled(step == .power)
                Spacer()
                if step == .save {
                    Button("Finish") {
                        model.finishCommissioningProfile()
                        model.setCalibrationWizardOpen(false)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.steel)
                    .disabled(!oversizeRejected || !boundaryReady)
                } else {
                    Button("Continue") { goNext() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.steel)
                        .disabled(!canContinue)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .power: powerStep
        case .head: headStep
        case .direction: directionStep
        case .endStops: endStopsStep
        case .homing: homingStep
        case .travel: travelStepView
        case .limits: limitsStep
        case .pen: penStep
        case .accuracy: accuracyStep
        case .safety: safetyStep
        case .save: saveStep
        }
    }

    private var powerStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Power and connection",
                "USB alone can show Connected while motors are dead. Missed steps make every measurement unreliable — block motion calibration until 12 V is confirmed."
            )
            if !model.isConnected {
                HelpCard(
                    title: "Connect first",
                    message: "Finish Setup → Connect, then return here.",
                    tone: .caution
                )
            }
            Toggle("Regulated 12 V DC adapter is plugged in and powered", isOn: $power12V)
            Toggle("Controller POWER LED is on (blue board switch)", isOn: $powerLED)
            Toggle(
                "I confirm motors have power — not USB-only",
                isOn: Binding(
                    get: { model.motorsPowerConfirmed },
                    set: { model.confirmMotorsPowered($0) }
                )
            )
            .disabled(!(power12V && powerLED && model.isConnected))
            HelpCard(
                title: "Why this gate exists",
                message: "Low or missing motor voltage skips steps. Direction, homing, and travel measurements would all be wrong.",
                tone: .info
            )
        }
    }

    private var headStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Select pen-head type", "T-A4 motor pen uses a four-wire stepper. Three-wire hobby servo heads store separate up/down angles.")
            ForEach(PenHeadType.allCases) { type in
                Button {
                    model.machine.penHeadType = type
                    model.persistMachine()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.machine.penHeadType == type ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.machine.penHeadType == type ? Theme.ok : Theme.inkMuted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(type.displayName)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(type.detail)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .quillGlass(
                        tint: model.machine.penHeadType == type ? Theme.steel.opacity(0.2) : nil,
                        shape: .rect(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var directionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Direction test",
                "Park the carriage near the middle. Keep the pen raised. For each axis: jog 5 mm, then tap Moved correctly — or Flip if it went the wrong way, jog again, and confirm."
            )
            motionGateBanner

            // Checklist — Continue stays off until both are confirmed.
            HStack(spacing: 16) {
                directionChecklistRow(axis: "X", ok: xDirectionOK)
                directionChecklistRow(axis: "Y", ok: yDirectionOK)
            }

            if !xDirectionOK || !yDirectionOK {
                HelpCard(
                    title: "Confirm each axis to continue",
                    message: !xDirectionOK && !yDirectionOK
                        ? "Jog X, then tap “X moved correctly”. Repeat for Y. Flipping an axis clears its check — jog once more and confirm again."
                        : (!xDirectionOK
                           ? "X still needs confirmation: jog X +5 mm, then tap “X moved correctly”."
                           : "Y still needs confirmation: jog Y +5 mm, then tap “Y moved correctly”."),
                    tone: .caution
                )
            }

            Group {
                Text("X axis")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                HStack(spacing: 10) {
                    Button("Pen up") { model.penUp() }
                        .disabled(!model.canCalibrateMotion)
                    Button("Jog X +5 mm") {
                        model.jogStep = 5
                        model.jog(dx: 5, dy: 0)
                    }
                    .disabled(!model.canCalibrateMotion)
                    Button("X moved correctly") { xDirectionOK = true }
                        .buttonStyle(.borderedProminent)
                        .tint(xDirectionOK ? Theme.ok : Theme.steel)
                        .disabled(!model.isConnected)
                    Button("X reversed — flip") {
                        model.flipAxisInvert(.x)
                        xDirectionOK = false
                    }
                    .disabled(!model.canCalibrateMotion)
                }
            }

            Group {
                Text("Y axis")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                HStack(spacing: 10) {
                    Button("Jog Y +5 mm") {
                        model.jogStep = 5
                        model.jog(dx: 0, dy: 5)
                    }
                    .disabled(!model.canCalibrateMotion)
                    Button("Y moved correctly") { yDirectionOK = true }
                        .buttonStyle(.borderedProminent)
                        .tint(yDirectionOK ? Theme.ok : Theme.steel)
                        .disabled(!model.isConnected)
                    Button("Y reversed — flip") {
                        model.flipAxisInvert(.y)
                        yDirectionOK = false
                    }
                    .disabled(!model.canCalibrateMotion)
                }
            }

            Text(
                "Controller $3 = \(model.machine.directionInvertMask)"
                    + " · X \(model.machine.invertX ? "flipped" : "normal")"
                    + " · Y \(model.machine.invertY ? "flipped" : "normal")"
                    + (model.machine.invertZ ? " · Z flipped (pen lift)" : "")
            )
            .font(Theme.captionFont)
            .foregroundStyle(Theme.inkMuted)
        }
    }

    private func directionChecklistRow(axis: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Theme.ok : Theme.inkMuted)
            Text("\(axis) \(ok ? "confirmed" : "not confirmed")")
                .font(Theme.captionFont.weight(.semibold))
                .foregroundStyle(ok ? Theme.ok : Theme.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .quillGlass(tint: ok ? Theme.ok.opacity(0.18) : nil, shape: .capsule)
    }

    private var endStopsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "End-stop test",
                "With motors stationary, press each switch by hand. The app must see it go active, then clear when released. Do not home until both pass."
            )
            motionGateBanner
            HStack(spacing: 10) {
                Button("Refresh status") { model.requestStatus() }
                Button("Reset switch checks") {
                    xSwitchSawOff = !model.status.pins.x
                    xSwitchSawOn = false
                    ySwitchSawOff = !model.status.pins.y
                    ySwitchSawOn = false
                    endStopBlocked = model.status.pins.x || model.status.pins.y
                }
            }
            if endStopBlocked || model.status.pins.anyXYLimit {
                HelpCard(
                    title: "Switch stuck active",
                    message: "A limit pin is reporting active while idle. Clear the switch or wiring before homing.",
                    tone: .danger
                )
            }
            pinRow(title: "X switch", active: model.status.pins.x, sawOff: xSwitchSawOff, sawOn: xSwitchSawOn)
            pinRow(title: "Y switch", active: model.status.pins.y, sawOff: ySwitchSawOff, sawOn: ySwitchSawOn)
            Text("Live pins: \(model.status.raw.isEmpty ? "waiting for status…" : model.status.raw)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.inkMuted)
                .textSelection(.enabled)
        }
        .onAppear {
            model.requestStatus()
            if model.status.pins.x || model.status.pins.y {
                endStopBlocked = true
            }
            xSwitchSawOff = !model.status.pins.x
            ySwitchSawOff = !model.status.pins.y
        }
    }

    private var homingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Homing test",
                "Raise the pen. Home X and Y only at low speed. Each axis must move toward its switch, touch it, back off slightly, and stop. Stop immediately if an axis runs away. Z is not homed."
            )
            motionGateBanner
            HStack(spacing: 10) {
                Button("Enable homing ($22=1)") { model.enableHomingSetting() }
                    .disabled(!model.canCalibrateMotion)
                Button("Pen up") { model.penUp() }
                    .disabled(!model.canCalibrateMotion)
                Button("Home X/Y") {
                    homingStarted = true
                    model.homeXY()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.steel)
                .disabled(!model.canCalibrateMotion || endStopsIncomplete)
            }
            Text("Watch the gantry: toward switch → click → small backoff → Idle. Use Emergency Stop if it moves away from a switch.")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.inkMuted)
            Toggle("Both axes homed correctly (toward switch, touch, backoff, stop)", isOn: $homingStarted)
                .disabled(!model.canCalibrateMotion)
        }
    }

    private var travelStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Measure safe travel",
                "After homing, move toward the opposite end in 10 mm steps, then 1 mm near the edge. Stop 3–5 mm before mechanical collision. Do not assume every unit reaches 200×300 mm."
            )
            motionGateBanner
            Picker("Axis", selection: $measuringAxis) {
                Text("X").tag(CalibrationAxis.x)
                Text("Y").tag(CalibrationAxis.y)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Picker("Step", selection: $travelStep) {
                Text("10 mm").tag(10.0)
                Text("1 mm").tag(1.0)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            HStack(spacing: 10) {
                Button("Pen up") { model.penUp() }
                    .disabled(!model.canCalibrateMotion)
                Button("Jog +step") {
                    model.jogStep = travelStep
                    switch measuringAxis {
                    case .x: model.jog(dx: travelStep, dy: 0)
                    case .y: model.jog(dx: 0, dy: travelStep)
                    }
                }
                .disabled(!model.canCalibrateMotion)
                Button("Jog −step") {
                    model.jogStep = travelStep
                    switch measuringAxis {
                    case .x: model.jog(dx: -travelStep, dy: 0)
                    case .y: model.jog(dx: 0, dy: -travelStep)
                    }
                }
                .disabled(!model.canCalibrateMotion)
            }
            HStack {
                Text("Safe X mm")
                TextField("", value: $travelX, format: .number)
                    .frame(width: 72)
                Text("Safe Y mm")
                TextField("", value: $travelY, format: .number)
                    .frame(width: 72)
                Button("Use conservative \(Int(MachineProfile.conservativeTravelX))×\(Int(MachineProfile.conservativeTravelY))") {
                    travelX = MachineProfile.conservativeTravelX
                    travelY = MachineProfile.conservativeTravelY
                }
                .font(Theme.captionFont)
            }
            Text(String(
                format: "Machine position X %.1f · Y %.1f — enter the distance from home to your stop point as safe travel.",
                model.status.mpos.x, model.status.mpos.y
            ))
            .font(Theme.captionFont)
            .foregroundStyle(Theme.inkMuted)
        }
    }

    private var limitsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Enable software limits",
                "Write safe travel to $130/$131, enable homing ($22), then soft limits ($20). Enable $20 only after homing works. Soft limits need a valid machine position — home again after every restart."
            )
            motionGateBanner
            Text(String(format: "Will write $130=%.0f  $131=%.0f  $22=1  $20=1", travelX, travelY))
                .font(.system(.body, design: .monospaced))
            Toggle("Also enable hard limits ($21=1) — optional", isOn: $enableHardLimits)
            Button("Write travel + enable limits") {
                model.enableHomingSetting()
                model.applySafeTravelAndLimits(
                    travelX: travelX,
                    travelY: travelY,
                    enableSoftLimits: true,
                    enableHardLimits: enableHardLimits
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.steel)
            .disabled(!model.canCalibrateMotion)
            if model.machine.softLimitsEnabled {
                HelpCard(
                    title: "Soft limits on",
                    message: "Home X/Y after every power cycle before plotting. Soft limits are meaningless until the controller knows where home is.",
                    tone: .ok
                )
            }
        }
    }

    private var penStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Calibrate the pen",
                model.machine.penHeadType == .motor
                    ? "Motor head: raise ≈5 mm above paper, lower in small steps until it writes, then add only minimal extra pressure (Bachin often ~2–5 in their UI; Quill GRBL Z-up uses higher = raised)."
                    : "Servo head: start from a neutral angle, raise until safe clearance, then lower gradually until the pen writes. Store separate up/down angles."
            )
            motionGateBanner
            if model.machine.penHeadType == .motor {
                HStack {
                    Text("Pen up Z")
                    TextField("", value: $model.machine.penUpZ, format: .number)
                        .frame(width: 56)
                        .onSubmit { model.clampPenHeightsToBachinRange(); model.persistMachine() }
                    Text("Pen down Z")
                    TextField("", value: $model.machine.penDownZ, format: .number)
                        .frame(width: 56)
                        .onSubmit { model.clampPenHeightsToBachinRange(); model.persistMachine() }
                    Button("Recommended 5 / 0") {
                        model.applyRecommendedPenHeights()
                    }
                }
                HStack(spacing: 10) {
                    Button("Pen up") { model.penUp() }
                    Button("Pen down") { model.penDown() }
                    Button("Nudge down 0.2") {
                        model.machine.penDownZ = max(0, model.machine.penDownZ - 0.2)
                        model.clampPenHeightsToBachinRange()
                        model.persistMachine()
                        model.penDown()
                    }
                }
                .disabled(!model.canCalibrateMotion)
            } else {
                HStack {
                    Text("Up angle")
                    TextField("", value: $model.machine.penUpAngle, format: .number)
                        .frame(width: 56)
                        .onSubmit { model.persistMachine() }
                    Text("Down angle")
                    TextField("", value: $model.machine.penDownAngle, format: .number)
                        .frame(width: 56)
                        .onSubmit { model.persistMachine() }
                }
                Text("Angles are stored on the machine profile. Keep clearance safe before any write test.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var accuracyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Accuracy test",
                "Command 100 mm on X and Y (pen can mark or you measure travel). If scaling is wrong: new_steps = old × commanded ÷ measured."
            )
            motionGateBanner
            HStack(spacing: 10) {
                Button("Pen up") { model.penUp() }
                Button("Move X 100 mm") {
                    model.jogStep = 100
                    model.jog(dx: 100, dy: 0)
                }
                Button("Move Y 100 mm") {
                    model.jogStep = 100
                    model.jog(dx: 0, dy: 100)
                }
            }
            .disabled(!model.canCalibrateMotion)
            HStack {
                Text("Measured X mm")
                TextField("", text: $measuredX)
                    .frame(width: 64)
                Button("Apply X steps/mm") {
                    if let m = Double(measuredX) {
                        model.applyDistanceCalibration(axis: .x, commandedMm: 100, measuredMm: m)
                        scaleApplied = true
                    }
                }
            }
            HStack {
                Text("Measured Y mm")
                TextField("", text: $measuredY)
                    .frame(width: 64)
                Button("Apply Y steps/mm") {
                    if let m = Double(measuredY) {
                        model.applyDistanceCalibration(axis: .y, commandedMm: 100, measuredMm: m)
                        scaleApplied = true
                    }
                }
            }
            .disabled(!model.canCalibrateMotion)
            Text(String(
                format: "Current steps/mm X %@ · Y %@",
                fmtOpt(model.machine.stepsPerMmX),
                fmtOpt(model.machine.stepsPerMmY)
            ))
            .font(Theme.captionFont)
            .foregroundStyle(Theme.inkMuted)
            Toggle("Scale checked (or already accurate)", isOn: $scaleApplied)
        }
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Final safety test",
                "Keep the pen raised. Trace the boundary rectangle, then verify a deliberately oversized job is rejected before any motion commands are sent."
            )
            motionGateBanner
            HStack(spacing: 10) {
                Button("Prepare boundary + oversize check") {
                    let result = model.runCommissioningSafetyTests()
                    boundaryReady = true
                    oversizeRejected = result.oversizeRejected
                    model.loadJob(text: result.boundaryGCode, name: "Boundary-frame.gcode", isSVG: false)
                }
                .disabled(!model.canCalibrateMotion)
                Button("Trace boundary (Start)") {
                    model.startJob()
                }
                .disabled(!model.canCalibrateMotion || !boundaryReady || !oversizeRejected)
                .help("Streams the raised-pen boundary rectangle already loaded")
            }
            if boundaryReady {
                HelpCard(
                    title: oversizeRejected ? "Oversize rejected" : "Oversize NOT rejected",
                    message: oversizeRejected
                        ? "Preflight correctly blocked a job past soft travel. Boundary G-code is loaded — Frame with pen raised when ready."
                        : "Preflight failed to reject an oversized path. Check travel limits before finishing.",
                    tone: oversizeRejected ? .ok : .danger
                )
            }
        }
    }

    private var saveStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(
                "Save machine profile",
                "Persist head type, safe travel, direction, steps/mm, homing/limits, pen up/down, and firmware as one profile."
            )
            profileSummary
            Button("Save profile now") {
                model.finishCommissioningProfile()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.steel)
        }
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Head: \(model.machine.penHeadType.displayName)")
            Text(String(format: "Travel: %.0f × %.0f mm", model.machine.travelX, model.machine.travelY))
            Text("Invert $3: \(model.machine.directionInvertMask)")
            Text(String(
                format: "Steps/mm: X %@ · Y %@",
                fmtOpt(model.machine.stepsPerMmX),
                fmtOpt(model.machine.stepsPerMmY)
            ))
            Text("$20 soft \(model.machine.softLimitsEnabled ? "on" : "off") · $21 hard \(model.machine.hardLimitsEnabled ? "on" : "off") · $22 homing \(model.machine.homingEnabled ? "on" : "off")")
            if model.machine.penHeadType == .motor {
                Text(String(format: "Pen Z up %.1f · down %.1f", model.machine.penUpZ, model.machine.penDownZ))
            } else {
                Text(String(format: "Pen angles up %.0f° · down %.0f°", model.machine.penUpAngle, model.machine.penDownAngle))
            }
            Text("Firmware: \(model.machine.buildInfo ?? model.firmwareAssessment.versionLabel)")
                .textSelection(.enabled)
        }
        .font(Theme.captionFont)
        .foregroundStyle(Theme.inkMuted)
    }

    // MARK: - Helpers

    private var motionGateBanner: some View {
        Group {
            if !model.canCalibrateMotion {
                HelpCard(
                    title: model.isConnected
                        ? (model.isAlarm ? "Machine locked" : "Power not confirmed")
                        : "Not connected",
                    message: model.isConnected
                        ? (model.isAlarm
                           ? "Unlock before any calibration motion."
                           : "Return to Power check and confirm 12 V + POWER LED. USB-only connection is not enough.")
                        : "Connect in Setup first.",
                    tone: .danger,
                    actionTitle: model.isAlarm ? "Unlock" : nil,
                    onAction: model.isAlarm ? { model.unlock() } : nil
                )
            }
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pinRow(title: String, active: Bool, sawOff: Bool, sawOn: Bool) -> some View {
        let passed = sawOff && sawOn && !active
        return HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            Text(active ? "ACTIVE" : "clear")
                .font(.caption.monospaced())
                .foregroundStyle(active ? Theme.caution : Theme.inkMuted)
            Text(passed ? "Pass" : "Press & release")
                .font(.caption.weight(.semibold))
                .foregroundStyle(passed ? Theme.ok : Theme.inkMuted)
        }
        .padding(10)
        .quillGlass(tint: passed ? Theme.ok.opacity(0.15) : nil, shape: .rect(cornerRadius: 12))
    }

    private var endStopsIncomplete: Bool {
        endStopBlocked || !(xSwitchSawOff && xSwitchSawOn && ySwitchSawOff && ySwitchSawOn)
            || model.status.pins.anyXYLimit
    }

    private var canContinue: Bool {
        switch step {
        case .power:
            return model.isConnected && power12V && powerLED && model.motorsPowerConfirmed
        case .head:
            return true
        case .direction:
            // Direction confirmations are explicit UI checks; don't strand the user if
            // a transient Alarm clears canCalibrateMotion after a successful jog.
            return model.isConnected && xDirectionOK && yDirectionOK
        case .endStops:
            return model.canCalibrateMotion && !endStopsIncomplete
        case .homing:
            return model.canCalibrateMotion && homingStarted
        case .travel:
            return model.canCalibrateMotion && travelX > 10 && travelY > 10
        case .limits:
            return model.machine.softLimitsEnabled && model.machine.homingEnabled
        case .pen:
            return true
        case .accuracy:
            return scaleApplied
        case .safety:
            return boundaryReady && oversizeRejected
        case .save:
            return true
        }
    }

    private var continueBlockedHint: String? {
        switch step {
        case .direction:
            if !model.isConnected { return "Connect in Setup before continuing." }
            if !xDirectionOK && !yDirectionOK {
                return "Tap “X moved correctly” and “Y moved correctly” after each jog."
            }
            if !xDirectionOK { return "Confirm X: jog, then tap “X moved correctly”." }
            if !yDirectionOK { return "Confirm Y: jog, then tap “Y moved correctly”." }
            return nil
        case .endStops:
            return endStopsIncomplete ? "Press and release both end switches until both show Pass." : nil
        case .homing:
            return homingStarted ? nil : "Run Home X/Y, then check “Both axes homed correctly”."
        case .limits:
            return "Tap “Write travel + enable limits” before continuing."
        case .accuracy:
            return scaleApplied ? nil : "Apply X/Y steps or check “Scale checked”."
        case .safety:
            return "Run the boundary + oversize check until oversize is rejected."
        default:
            return nil
        }
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        if next == .endStops {
            endStopBlocked = model.status.pins.x || model.status.pins.y
            xSwitchSawOff = !model.status.pins.x
            ySwitchSawOff = !model.status.pins.y
            xSwitchSawOn = false
            ySwitchSawOn = false
        }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = prev }
    }

    private func fmtOpt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.3f", v)
    }
}
