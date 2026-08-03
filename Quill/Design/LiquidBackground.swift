import SwiftUI

/// Atmospheric backdrop so Liquid Glass panels have something to refract.
struct LiquidBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            canvas(at: t)
        }
        .ignoresSafeArea()
        .overlay { washOverlay }
    }

    private var washOverlay: some View {
        LinearGradient(
            colors: [
                Theme.paper.opacity(0.15),
                Theme.ink.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func canvas(at t: TimeInterval) -> some View {
        Canvas { context, size in
            paint(context: context, size: size, t: t)
        }
    }

    private func paint(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(Theme.paper))

        let c1 = CGPoint(
            x: size.width * (0.22 + 0.04 * sin(t * 0.35)),
            y: size.height * (0.28 + 0.05 * cos(t * 0.28))
        )
        drawBlob(context: context, center: c1, radius: size.width * 0.42, color: Theme.steelBright.opacity(0.28))

        let c2 = CGPoint(
            x: size.width * (0.78 + 0.03 * cos(t * 0.22)),
            y: size.height * (0.62 + 0.04 * sin(t * 0.31))
        )
        drawBlob(context: context, center: c2, radius: size.width * 0.48, color: Theme.steel.opacity(0.22))

        let c3 = CGPoint(
            x: size.width * (0.55 + 0.05 * sin(t * 0.18)),
            y: size.height * (0.88 + 0.03 * cos(t * 0.25))
        )
        drawBlob(context: context, center: c3, radius: size.width * 0.38, color: Theme.mist.opacity(0.55))
    }

    private func drawBlob(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let gradient = Gradient(colors: [color, color.opacity(0)])
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        )
    }
}
