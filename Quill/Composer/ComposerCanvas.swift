import SwiftUI
import AppKit
import CNCCore

/// Bed + paper canvas with rulers, grid, element frames, drag, and plot-aware preview.
struct ComposerCanvas: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geo in
                let bedW = model.machine.travelX
                let bedH = model.machine.travelY
                let base = min(geo.size.width / bedW, geo.size.height / bedH) * 0.88
                let scale = base * model.canvasZoom
                let ox = (geo.size.width - bedW * scale) / 2
                let oy = (geo.size.height - bedH * scale) / 2

                ZStack(alignment: .topLeading) {
                    Color(nsColor: .controlBackgroundColor)

                    rulerH(width: bedW * scale, scale: scale)
                        .offset(x: ox, y: max(oy - 18, 0))
                    rulerV(height: bedH * scale, scale: scale)
                        .offset(x: max(ox - 18, 0), y: oy)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.20, blue: 0.22),
                                    Color(red: 0.12, green: 0.13, blue: 0.15),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: bedW * scale, height: bedH * scale)
                        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                        .position(x: ox + bedW * scale / 2, y: oy + bedH * scale / 2)

                    paperLayer(ox: ox, oy: oy, scale: scale, bedH: bedH)

                    if model.page.editor.showGrid {
                        gridOverlay(ox: ox, oy: oy, scale: scale, bedH: bedH)
                    }

                    ForEach(model.page.editor.guides) { guide in
                        guideLine(guide, ox: ox, oy: oy, scale: scale, bedH: bedH)
                    }

                    pathPreview(ox: ox, oy: oy, scale: scale, bedH: bedH)
                    elementFrames(ox: ox, oy: oy, scale: scale, bedH: bedH)

                    Text("Bed \(Int(bedW))×\(Int(bedH)) mm · zoom \(Int(model.canvasZoom * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .gesture(dragGesture(ox: ox, oy: oy, scale: scale, bedH: bedH))
            }
            nudgeBar
        }
        .onAppear { installKeyMonitor() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("-") { model.canvasZoom = max(0.4, model.canvasZoom - 0.1) }
            Button("100%") { model.canvasZoom = 1 }
            Button("Fit") { model.canvasZoom = 1 }
            Button("+") { model.canvasZoom = min(3, model.canvasZoom + 0.1) }
            Toggle("Travel", isOn: $model.showTravelPaths)
            Spacer()
            if let warn = model.composedPage?.warnings.first {
                Text(warn)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var nudgeBar: some View {
        HStack(spacing: 8) {
            Text("Nudge").font(.caption2).foregroundStyle(.secondary)
            Button("←") { model.nudgeSelected(dx: -model.page.editor.nudgeNormalMm, dy: 0) }
            Button("→") { model.nudgeSelected(dx: model.page.editor.nudgeNormalMm, dy: 0) }
            Button("↑") { model.nudgeSelected(dx: 0, dy: model.page.editor.nudgeNormalMm) }
            Button("↓") { model.nudgeSelected(dx: 0, dy: -model.page.editor.nudgeNormalMm) }
            Text("Shift = 10 mm · Option = 0.1 mm / no snap")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func paperLayer(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some View {
        let page = model.page
        let px = ox + page.bedOriginX * scale
        let py = oy + (bedH - page.bedOriginY - page.format.heightMm) * scale
        let margin = page.editor.marginMm * scale
        return ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: page.format.widthMm * scale, height: page.format.heightMm * scale)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
            Rectangle()
                .strokeBorder(Color.orange.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(
                    width: max(page.format.widthMm * scale - margin * 2, 1),
                    height: max(page.format.heightMm * scale - margin * 2, 1)
                )
        }
        .position(
            x: px + page.format.widthMm * scale / 2,
            y: py + page.format.heightMm * scale / 2
        )
    }

    private func gridOverlay(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some View {
        let page = model.page
        let spacing = page.editor.gridSpacingMm
        let px = ox + page.bedOriginX * scale
        let py = oy + (bedH - page.bedOriginY - page.format.heightMm) * scale
        return Path { path in
            var x = 0.0
            while x <= page.format.widthMm + 0.01 {
                let sx = px + x * scale
                path.move(to: CGPoint(x: sx, y: py))
                path.addLine(to: CGPoint(x: sx, y: py + page.format.heightMm * scale))
                x += spacing
            }
            var y = 0.0
            while y <= page.format.heightMm + 0.01 {
                let sy = py + (page.format.heightMm - y) * scale
                path.move(to: CGPoint(x: px, y: sy))
                path.addLine(to: CGPoint(x: px + page.format.widthMm * scale, y: sy))
                y += spacing
            }
        }
        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
    }

    private func guideLine(_ guide: GuideLine, ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some View {
        let page = model.page
        let px = ox + page.bedOriginX * scale
        let py = oy + (bedH - page.bedOriginY - page.format.heightMm) * scale
        return Path { path in
            switch guide.orientation {
            case .vertical:
                let x = px + guide.positionMm * scale
                path.move(to: CGPoint(x: x, y: py))
                path.addLine(to: CGPoint(x: x, y: py + page.format.heightMm * scale))
            case .horizontal:
                let y = py + (page.format.heightMm - guide.positionMm) * scale
                path.move(to: CGPoint(x: px, y: y))
                path.addLine(to: CGPoint(x: px + page.format.widthMm * scale, y: y))
            }
        }
        .stroke(Color.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }

    private func pathPreview(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some View {
        Group {
            if let job = model.previewJob {
                if model.showTravelPaths {
                    Path { path in
                        var last: CGPoint?
                        for cmd in job.commands {
                            switch cmd {
                            case .move(let p):
                                let pt = CGPoint(x: ox + p.x * scale, y: oy + (bedH - p.y) * scale)
                                if let last {
                                    path.move(to: last)
                                    path.addLine(to: pt)
                                }
                                last = pt
                            case .line(let p):
                                last = CGPoint(x: ox + p.x * scale, y: oy + (bedH - p.y) * scale)
                            case .penChange:
                                last = nil
                            }
                        }
                    }
                    .stroke(Color.yellow.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                }

                Path { path in
                    var started = false
                    for cmd in job.commands {
                        switch cmd {
                        case .move(let p):
                            let pt = CGPoint(x: ox + p.x * scale, y: oy + (bedH - p.y) * scale)
                            path.move(to: pt)
                            started = true
                        case .line(let p):
                            let pt = CGPoint(x: ox + p.x * scale, y: oy + (bedH - p.y) * scale)
                            if started { path.addLine(to: pt) }
                            else { path.move(to: pt); started = true }
                        case .penChange:
                            started = false
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 1.2)
            }
        }
    }

    private func elementFrames(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some View {
        ForEach(model.page.elements.filter(\.visible)) { el in
            let origin = el.frameOriginPaper
            let page = model.page
            let x = ox + (page.bedOriginX + origin.x) * scale
            let y = oy + (bedH - (page.bedOriginY + origin.y + el.heightMm * el.scale)) * scale
            let selected = model.selectedElementIDs.contains(el.id) || model.selectedElementID == el.id
            Rectangle()
                .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.25), lineWidth: selected ? 1.5 : 0.8)
                .background(Color.accentColor.opacity(selected ? 0.08 : 0.02))
                .frame(width: max(el.widthMm * el.scale * scale, 4), height: max(el.heightMm * el.scale * scale, 4))
                .rotationEffect(.degrees(-el.rotationDegrees))
                .position(
                    x: x + el.widthMm * el.scale * scale / 2,
                    y: y + el.heightMm * el.scale * scale / 2
                )
                .onTapGesture {
                    model.selectElement(el.id, additive: NSEvent.modifierFlags.contains(.shift))
                }
        }
    }

    private func dragGesture(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let id = model.selectedElementID,
                      let el = model.page.elements.first(where: { $0.id == id }),
                      !el.locked else { return }
                if !isDragging {
                    isDragging = true
                    model.beginDragGesture()
                }
                let paperX = (value.location.x - ox) / scale - model.page.bedOriginX
                let paperY = bedH - (value.location.y - oy) / scale - model.page.bedOriginY
                let disableSnap = NSEvent.modifierFlags.contains(.option)
                model.dragSelected(toPaperX: paperX, y: paperY, disableSnap: disableSnap)
            }
            .onEnded { _ in
                isDragging = false
                model.endGeometryEdit()
            }
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let fine = model.page.editor.nudgeFineMm
            let normal = model.page.editor.nudgeNormalMm
            let large = model.page.editor.nudgeLargeMm
            let step = flags.contains(.shift) ? large : flags.contains(.option) ? fine : normal
            let disableSnap = flags.contains(.option)
            switch event.keyCode {
            case 123: model.nudgeSelected(dx: -step, dy: 0, disableSnap: disableSnap); return nil
            case 124: model.nudgeSelected(dx: step, dy: 0, disableSnap: disableSnap); return nil
            case 126: model.nudgeSelected(dx: 0, dy: step, disableSnap: disableSnap); return nil
            case 125: model.nudgeSelected(dx: 0, dy: -step, disableSnap: disableSnap); return nil
            case 51, 117:
                model.deleteSelectedElement(); return nil
            default:
                if flags.contains(.command) {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "z" where flags.contains(.shift):
                        model.redoDocument(); return nil
                    case "z":
                        model.undoDocument(); return nil
                    case "c":
                        model.copySelectedElements(); return nil
                    case "v":
                        model.pasteClipboardElements(); return nil
                    case "d":
                        model.duplicateSelectedElement(); return nil
                    default:
                        break
                    }
                }
                return event
            }
        }
    }

    private func rulerH(width: CGFloat, scale: CGFloat) -> some View {
        Canvas { ctx, size in
            let step = max(model.page.editor.gridSpacingMm * scale, 8)
            var x: CGFloat = 0
            while x <= width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 12))
                path.addLine(to: CGPoint(x: x, y: 18))
                ctx.stroke(path, with: .color(.secondary), lineWidth: 1)
                x += step
            }
        }
        .frame(width: width, height: 18)
    }

    private func rulerV(height: CGFloat, scale: CGFloat) -> some View {
        Canvas { ctx, size in
            let step = max(model.page.editor.gridSpacingMm * scale, 8)
            var y: CGFloat = 0
            while y <= height {
                var path = Path()
                path.move(to: CGPoint(x: 12, y: y))
                path.addLine(to: CGPoint(x: 18, y: y))
                ctx.stroke(path, with: .color(.secondary), lineWidth: 1)
                y += step
            }
        }
        .frame(width: 18, height: height)
    }
}
