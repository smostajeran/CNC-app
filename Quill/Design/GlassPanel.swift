import SwiftUI

/// Liquid Glass–inspired panel (frosted material + tint; morphs with LiquidBackground).
struct GlassPanel<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quillGlass(tint: tint, shape: .rect(cornerRadius: 22))
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
            .quillGlass(tint: tint, shape: .capsule)
    }
}

/// Groups interactive glass controls.
struct GlassEffectContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}

enum QuillGlassShape {
    case capsule
    case rect(cornerRadius: CGFloat)
}

extension View {
    /// Frosted glass treatment matching the hobbyist Liquid Glass system.
    @ViewBuilder
    func quillGlass(tint: Color? = nil, shape: QuillGlassShape, interactive: Bool = false) -> some View {
        switch shape {
        case .capsule:
            background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill((tint ?? Theme.steelBright).opacity(interactive ? 0.28 : 0.18))
                    }
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.9)
                    }
            }
        case .rect(let radius):
            background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill((tint ?? Theme.steelBright).opacity(interactive ? 0.22 : 0.14))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    }
                    .shadow(color: Theme.ink.opacity(0.07), radius: interactive ? 10 : 18, y: interactive ? 4 : 8)
            }
        }
    }
}
