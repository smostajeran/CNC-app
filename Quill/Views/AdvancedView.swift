import SwiftUI

struct AdvancedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var consoleInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Advanced")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Recovery tools and raw commands. Most people can ignore this after Setup works.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(.secondary)
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("If something goes wrong")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("Unlock clears a locked (Alarm) state. Soft reset restarts the controller brain. Factory reset restores factory numbers — only if you know you need it.")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            EmergencyStopButton(compact: true)
                            Button("Unlock") { model.unlock() }
                            Button("Soft reset") { model.softReset() }
                            Button("Factory reset…", role: .destructive) {
                                model.requestFactoryReset()
                            }
                        }
                        .disabled(!model.isConnected)
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mirrored or backwards writing")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Toggle("Flip left ↔ right (X)", isOn: $model.machine.invertX)
                        Toggle("Flip front ↔ back (Y)", isOn: $model.machine.invertY)
                        Toggle("Flip pen lift (Z)", isOn: $model.machine.invertZ)
                        Button("Save flips to machine") {
                            model.applyInvertToController()
                        }
                        .disabled(!model.isConnected)
                        Text("Nudges in Move use these immediately. Save writes them into the controller for other apps too.")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.isConnected)

                GlassPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Console")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(model.console.enumerated()), id: \.offset) { idx, line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id(idx)
                                    }
                                }
                                .padding(8)
                            }
                            .frame(minHeight: 180, idealHeight: 240)
                            .onChange(of: model.console.count) { _ in
                                if let last = model.console.indices.last {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                        HStack {
                            TextField("Send a command (G-code, $$, $I…)", text: $consoleInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { sendConsole() }
                            Button("Send") { sendConsole() }
                                .disabled(!model.isConnected || consoleInput.isEmpty)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func sendConsole() {
        let line = consoleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        model.sendConsole(line)
        consoleInput = ""
    }
}
