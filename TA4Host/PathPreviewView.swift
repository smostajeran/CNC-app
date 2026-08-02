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
            var lastPoint: CGPoint?
            for cmd in drawable.commands {
                switch cmd {
                case .move(let p):
                    lastPoint = map(p)
                case .line(let p):
                    let next = map(p)
                    if let from = lastPoint {
                        var seg = Path()
                        seg.move(to: from)
                        seg.addLine(to: next)
                        let pressure = p.pressure ?? 0.5
                        let width = 0.8 + pressure * 2.2
                        let opacity = 0.4 + pressure * 0.6
                        context.stroke(
                            seg,
                            with: .color(.accentColor.opacity(opacity)),
                            lineWidth: width
                        )
                    }
                    lastPoint = next
                case .penChange:
                    lastPoint = nil
                }
            }
        }
        .accessibilityLabel("Path preview")
    }
}
