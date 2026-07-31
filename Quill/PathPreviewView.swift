import SwiftUI
import CNCCore

struct PathPreviewView: View {
    let job: PlotJob?
    let workspace: MachineProfile

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 20
            let drawW = max(size.width - pad * 2, 1)
            let drawH = max(size.height - pad * 2, 1)
            let sx = drawW / workspace.travelX
            let sy = drawH / workspace.travelY
            let scale = min(sx, sy)

            let bedRect = CGRect(
                x: pad,
                y: size.height - pad - workspace.travelY * scale,
                width: workspace.travelX * scale,
                height: workspace.travelY * scale
            )

            // Soft bed fill
            context.fill(
                Path(roundedRect: bedRect, cornerRadius: 8),
                with: .color(Theme.mist.opacity(0.55))
            )
            context.stroke(
                Path(roundedRect: bedRect, cornerRadius: 8),
                with: .color(Theme.steel.opacity(0.45)),
                lineWidth: 1.5
            )

            // Light grid
            let gridStep = 50.0 * scale
            if gridStep > 8 {
                var grid = Path()
                var x = bedRect.minX + gridStep
                while x < bedRect.maxX - 1 {
                    grid.move(to: CGPoint(x: x, y: bedRect.minY))
                    grid.addLine(to: CGPoint(x: x, y: bedRect.maxY))
                    x += gridStep
                }
                var y = bedRect.maxY - gridStep
                while y > bedRect.minY + 1 {
                    grid.move(to: CGPoint(x: bedRect.minX, y: y))
                    grid.addLine(to: CGPoint(x: bedRect.maxX, y: y))
                    y -= gridStep
                }
                context.stroke(grid, with: .color(Theme.steel.opacity(0.12)), lineWidth: 1)
            }

            func map(_ p: PlotPoint) -> CGPoint {
                CGPoint(
                    x: pad + p.x * scale,
                    y: size.height - pad - p.y * scale
                )
            }

            guard let job, !job.commands.isEmpty else {
                context.draw(
                    Text("Open an SVG or G-code drawing to see the path here")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(Theme.steel.opacity(0.85)),
                    at: CGPoint(x: size.width / 2, y: size.height / 2),
                    anchor: .center
                )
                return
            }

            var path = Path()
            var started = false
            for cmd in job.commands {
                switch cmd {
                case .move(let p):
                    path.move(to: map(p))
                    started = true
                case .line(let p):
                    if !started {
                        path.move(to: map(p))
                        started = true
                    } else {
                        path.addLine(to: map(p))
                    }
                }
            }
            context.stroke(path, with: .color(Theme.steelBright.opacity(0.55)), lineWidth: 3.2)
            context.stroke(path, with: .color(Theme.ink.opacity(0.88)), lineWidth: 1.8)
        }
        .background(
            LinearGradient(
                colors: [Theme.paper, Theme.mist.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityLabel("Path preview")
    }
}
