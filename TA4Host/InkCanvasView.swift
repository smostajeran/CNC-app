import SwiftUI
import AppKit
import CNCCore

/// Pressure-aware handwriting capture over the machine workspace.
struct InkCanvasView: NSViewRepresentable {
    @Binding var document: InkDocument
    var workspace: MachineProfile
    var onStrokeEnd: (() -> Void)?

    func makeNSView(context: Context) -> InkNSView {
        let view = InkNSView()
        view.workspace = workspace
        view.document = document
        view.onChange = { doc in
            document = doc
        }
        view.onStrokeEnd = onStrokeEnd
        return view
    }

    func updateNSView(_ nsView: InkNSView, context: Context) {
        nsView.workspace = workspace
        if nsView.document != document {
            nsView.document = document
            nsView.needsDisplay = true
        }
        nsView.onStrokeEnd = onStrokeEnd
    }
}

final class InkNSView: NSView {
    var workspace = MachineProfile.ta4
    var document = InkDocument()
    var onChange: ((InkDocument) -> Void)?
    var onStrokeEnd: (() -> Void)?

    private var currentStroke = InkDocument.Stroke()
    private var lastPoint: CGPoint?
    private var lastTime: TimeInterval = 0
    private var lastMachine = PlotPoint(x: 0, y: 0)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Bed
        let pad: CGFloat = 12
        let sx = (bounds.width - pad * 2) / workspace.travelX
        let sy = (bounds.height - pad * 2) / workspace.travelY
        let scale = min(sx, sy)
        let bedW = workspace.travelX * scale
        let bedH = workspace.travelY * scale
        let origin = CGPoint(x: pad, y: pad)

        ctx.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: origin.x, y: origin.y, width: bedW, height: bedH))

        func map(_ p: PlotPoint) -> CGPoint {
            CGPoint(
                x: origin.x + p.x * scale,
                y: origin.y + p.y * scale
            )
        }

        func strokePath(_ stroke: InkDocument.Stroke) {
            guard let first = stroke.samples.first else { return }
            var prev = map(PlotPoint(x: first.x, y: first.y))
            for sample in stroke.samples.dropFirst() {
                let next = map(PlotPoint(x: sample.x, y: sample.y))
                let width = 0.8 + sample.pressure * 2.4
                let alpha = 0.35 + sample.pressure * 0.65
                ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(width)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.beginPath()
                ctx.move(to: prev)
                ctx.addLine(to: next)
                ctx.strokePath()
                prev = next
            }
        }

        for stroke in document.strokes {
            strokePath(stroke)
        }
        strokePath(currentStroke)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginStroke(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        continueStroke(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        continueStroke(with: event)
        endStroke()
    }

    override func tabletProximity(_ event: NSEvent) {
        // Ensure tablet events route here when stylus enters proximity.
        window?.makeFirstResponder(self)
    }

    private func beginStroke(with event: NSEvent) {
        currentStroke = InkDocument.Stroke()
        lastPoint = convert(event.locationInWindow, from: nil)
        lastTime = event.timestamp
        if let sample = sample(from: event) {
            currentStroke.samples.append(sample)
            lastMachine = PlotPoint(x: sample.x, y: sample.y)
        }
        needsDisplay = true
    }

    private func continueStroke(with event: NSEvent) {
        guard let sample = sample(from: event) else { return }
        currentStroke.samples.append(sample)
        lastMachine = PlotPoint(x: sample.x, y: sample.y)
        lastPoint = convert(event.locationInWindow, from: nil)
        lastTime = event.timestamp
        needsDisplay = true
    }

    private func endStroke() {
        guard currentStroke.samples.count >= 2 else {
            currentStroke = InkDocument.Stroke()
            needsDisplay = true
            return
        }
        document.strokes.append(currentStroke)
        document.travelX = workspace.travelX
        document.travelY = workspace.travelY
        currentStroke = InkDocument.Stroke()
        lastPoint = nil
        onChange?(document)
        onStrokeEnd?()
        needsDisplay = true
    }

    private func sample(from event: NSEvent) -> InkDocument.Sample? {
        let pad: CGFloat = 12
        let sx = (bounds.width - pad * 2) / workspace.travelX
        let sy = (bounds.height - pad * 2) / workspace.travelY
        let scale = min(sx, sy)
        let loc = convert(event.locationInWindow, from: nil)
        let mx = (loc.x - pad) / scale
        let my = (loc.y - pad) / scale
        guard mx >= -5, my >= -5, mx <= workspace.travelX + 5, my <= workspace.travelY + 5 else {
            return nil
        }
        let x = min(max(mx, 0), workspace.travelX)
        let y = min(max(my, 0), workspace.travelY)

        let pressure: Double
        if event.type == .tabletPoint || event.subtype == .tabletPoint {
            pressure = Double(event.pressure)
        } else if event.pressure > 0 {
            pressure = Double(event.pressure)
        } else if let lastPoint {
            let dx = loc.x - lastPoint.x
            let dy = loc.y - lastPoint.y
            let distPx = hypot(dx, dy)
            let distMm = Double(distPx / scale)
            let dt = max(event.timestamp - lastTime, 1e-3)
            pressure = InkCapture.syntheticPressure(distanceMm: distMm, dt: dt)
        } else {
            pressure = 0.55
        }

        return InkDocument.Sample(x: x, y: y, pressure: pressure)
    }

    func clear() {
        document.strokes.removeAll()
        currentStroke = InkDocument.Stroke()
        onChange?(document)
        needsDisplay = true
    }
}
