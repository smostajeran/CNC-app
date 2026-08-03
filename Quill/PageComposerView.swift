import SwiftUI
import CNCCore

/// True-size page on the machine bed with precision inspector, canvas, and layers.
struct PageComposerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            PrecisionInspector()
                .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
            VStack(spacing: 0) {
                ComposerCanvas()
                metricsBar
            }
            .frame(minWidth: 480)
            LayerObjectPanel()
                .frame(minWidth: 240, idealWidth: 270, maxWidth: 320)
        }
    }

    private var metricsBar: some View {
        HStack(spacing: 16) {
            Toggle("Optimize paths", isOn: $model.optimizePaths)
                .onChange(of: model.optimizePaths) { _ in model.recomposePage() }
            if let m = model.composedPage {
                metric("Draw", String(format: "%.0f mm", m.optimizedMetrics.drawDistanceMm))
                metric("Travel", String(format: "%.0f mm", m.optimizedMetrics.travelDistanceMm))
                metric("Pens", "\(m.optimizedMetrics.penChanges)")
                metric("ETA", m.optimizedMetrics.etaLabel)
                if m.hasBlockingOverflow {
                    Text("Overflow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if m.metrics.estimatedSeconds > m.optimizedMetrics.estimatedSeconds + 0.5 {
                    Text(String(
                        format: "saved %.0fs",
                        m.metrics.estimatedSeconds - m.optimizedMetrics.estimatedSeconds
                    ))
                    .font(.caption2)
                    .foregroundStyle(.green)
                }
            } else {
                Text("Add content to compose the page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Frame Page") { model.framePage() }
                .disabled(model.composedPage == nil || !model.allowsManualCommands)
            Button("Preflight & Run") { model.applyPageToJob() }
                .buttonStyle(.borderedProminent)
                .disabled(model.composedPage == nil || model.hasBlockingTextOverflow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced())
        }
    }
}
