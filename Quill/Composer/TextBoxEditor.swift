import SwiftUI
import CNCCore

struct TextBoxEditor: View {
    let text: String
    let style: TextBoxStyle
    let onChange: (String, TextBoxStyle) -> Void

    @State private var draftText: String = ""
    @State private var draftStyle: TextBoxStyle = TextBoxStyle()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paragraph").font(.subheadline.weight(.semibold))
            TextEditor(text: $draftText)
                .frame(minHeight: 90, maxHeight: 160)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
                .onChange(of: draftText) { _ in onChange(draftText, draftStyle) }
                .onDisappear { }

            let layout = TextLayoutEngine.layout(
                text: draftText,
                boxWidthMm: 120,
                boxHeightMm: 40,
                style: draftStyle
            )
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

            Picker("Font kind", selection: Binding(
                get: { draftStyle.fontKind },
                set: { draftStyle.fontKind = $0; onChange(draftText, draftStyle) }
            )) {
                Text("Single-line plotter").tag(FontKind.singleLinePlotter)
                Text("Outline").tag(FontKind.outline)
            }

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
                Text("Truncate (confirm)").tag(TextOverflowPolicy.truncateConfirmed)
            }

            Toggle("RTL", isOn: Binding(
                get: { draftStyle.isRTL },
                set: { draftStyle.isRTL = $0; onChange(draftText, draftStyle) }
            ))
        }
        .onAppear {
            draftText = text
            draftStyle = style
        }
        .onChange(of: text) { newValue in
            if newValue != draftText { draftText = newValue }
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
