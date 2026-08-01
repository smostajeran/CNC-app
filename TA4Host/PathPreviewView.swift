import SwiftUI
import CNCCore

struct PathPreviewView: View {
    let job: PlotJob?
    let workspace: MachineProfile

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 16
            let drawW = max(size.width - pad * 2, 1)
            let drawH = max(size.height - pad * 2, 1)
            let sx = drawW / workspace.travelX
            let sy = drawH / workspace.travelY
            let scale = min(sx, sy)

            func map(_ p: PlotPoint) -> CGPoint {
                // Machine origin bottom-left in preview
                CGPoint(
                    x: pad + p.x * scale,
                    y: size.height - pad - p.y * scale
                )
            }

            // Workspace outline
            var bed = Path()
            bed.addRect(CGRect(
                x: pad,
                y: size.height - pad - workspace.travelY * scale,
                width: workspace.travelX * scale,
                height: workspace.travelY * scale
            ))
            context.stroke(bed, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

            guard let job else {
                context.draw(
                    Text("Open a .gcode / .svg job to preview").foregroundColor(.secondary),
                    at: CGPoint(x: size.width / 2, y: size.height / 2),
                    anchor: .center
                )
                return
            }

            let drawable = job.simplified()
            var path = Path()
            var started = false
            for cmd in drawable.commands {
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
                case .penChange:
                    started = false
                }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .accessibilityLabel("Path preview")
    }
}
