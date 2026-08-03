import SwiftUI
import CNCCore

struct TextBoxEditor: View {
    let text: String
    let style: TextBoxStyle
    let boxWidthMm: Double
    let boxHeightMm: Double
    let onChange: (String, TextBoxStyle) -> Void
    let onEditingEnded: () -> Void

    @State private var draftText: String = ""
    @State private var draftStyle: TextBoxStyle = TextBoxStyle()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ParagraphTextEditor(
                label: "Paragraph text",
                text: $draftText,
                placeholder: "Type or paste a letter, address or paragraph…",
                onExpandCommitted: {
                    onChange(draftText, draftStyle)
                },
                onExpandCancelled: {
                    // Binding already restored snapshot inside ParagraphTextEditor.
                    onChange(draftText, draftStyle)
                }
            )
            .onChange(of: draftText) { _ in
                onChange(draftText, draftStyle)
            }
            .onDisappear { onEditingEnded() }

            let layout = TextLayoutEngine.layout(
                text: draftText,
                boxWidthMm: boxWidthMm,
                boxHeightMm: boxHeightMm,
                style: draftStyle
            )
            Text(String(format: "Box %.1f × %.1f mm", boxWidthMm, boxHeightMm))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if layout.overflows {
                Label(layout.overflowMessage ?? "Overflow", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !layout.missingGlyphs.isEmpty {
                Text("Missing glyphs: \(layout.missingGlyphs.map(String.init).joined())")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Only implemented font kinds are selectable.
            Text("Font: Single-line plotter")
                .font(.caption)
            Text("Outline fonts — not implemented")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Convert text to paths — not implemented")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                labeled("Size", value: Binding(
                    get: { draftStyle.fontSizeMm },
                    set: { draftStyle.fontSizeMm = $0; onChange(draftText, draftStyle) }
                ))
                labeled("Line", value: Binding(
                    get: { draftStyle.lineSpacingMm },
                    set: { draftStyle.lineSpacingMm = $0; onChange(draftText, draftStyle) }
                ))
                labeled("Para", value: Binding(
                    get: { draftStyle.paragraphSpacingMm },
                    set: { draftStyle.paragraphSpacingMm = $0; onChange(draftText, draftStyle) }
                ))
            }
            HStack {
                labeled("Pad", value: Binding(
                    get: { draftStyle.paddingMm },
                    set: { draftStyle.paddingMm = $0; onChange(draftText, draftStyle) }
                ))
                labeled("Letter", value: Binding(
                    get: { draftStyle.letterSpacingEm },
                    set: { draftStyle.letterSpacingEm = $0; onChange(draftText, draftStyle) }
                ))
                labeled("Baseline", value: Binding(
                    get: { draftStyle.baselineOffsetMm },
                    set: { draftStyle.baselineOffsetMm = $0; onChange(draftText, draftStyle) }
                ))
            }

            Picker("Align", selection: Binding(
                get: { draftStyle.alignment },
                set: { draftStyle.alignment = $0; onChange(draftText, draftStyle) }
            )) {
                Text("Left").tag(CNCCore.TextAlignment.left)
                Text("Centre").tag(CNCCore.TextAlignment.center)
                Text("Right").tag(CNCCore.TextAlignment.right)
            }
            .pickerStyle(.segmented)

            Picker("Height", selection: Binding(
                get: { draftStyle.heightMode },
                set: { draftStyle.heightMode = $0; onChange(draftText, draftStyle) }
            )) {
                Text("Automatic").tag(TextHeightMode.automatic)
                Text("Fixed").tag(TextHeightMode.fixed)
            }

            Picker("Overflow", selection: Binding(
                get: { draftStyle.overflowPolicy },
                set: { draftStyle.overflowPolicy = $0; onChange(draftText, draftStyle) }
            )) {
                Text("Show overflow").tag(TextOverflowPolicy.showOverflow)
                Text("Expand box").tag(TextOverflowPolicy.expandBox)
                Text("Reduce font").tag(TextOverflowPolicy.reduceFontSize)
            }
            Text("Truncate — not implemented")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("RTL", isOn: Binding(
                get: { draftStyle.isRTL },
                set: { draftStyle.isRTL = $0; onChange(draftText, draftStyle) }
            ))
        }
        .onAppear {
            draftText = text
            draftStyle = style
            if !draftStyle.fontKind.isImplemented {
                draftStyle.fontKind = .singleLinePlotter
            }
            if !draftStyle.overflowPolicy.isImplemented {
                draftStyle.overflowPolicy = .showOverflow
            }
        }
        .onChange(of: text) { newValue in
            if newValue != draftText { draftText = newValue }
        }
        .onChange(of: style) { newValue in
            if newValue != draftStyle { draftStyle = newValue }
        }
    }

    private func labeled(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
        }
    }
}
