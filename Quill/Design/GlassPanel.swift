import SwiftUI

/// Liquid Glass container for interactive clusters.
struct GlassPanel<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                tint.map { Glass.regular.tint($0) } ?? .regular,
                in: .rect(cornerRadius: 22)
            )
    }
}

/// Compact glass chip for status / labels.
struct GlassChip<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(
                tint.map { Glass.regular.tint($0) } ?? .regular,
                in: .capsule
            )
    }
}
