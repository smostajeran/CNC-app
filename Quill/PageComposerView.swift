import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

/// Canonical true-size Page Composer: page controls | bed canvas | Pen & Layer Studio.
/// Integrates precision millimetre editing without the alternate three-panel shell.
struct PageComposerView: View {
    @EnvironmentObject private var model: AppModel
    var onPreflightRun: (() -> Void)? = nil
    @State private var showLayoutTools = false
    @State private var showSelectedInspector = true
    @State private var isDragging = false
    @State private var keyMonitor: Any?
    @State private var showTravelPaths = true
    @State private var canvasZoom: Double = 1

    var body: some View {
        HSplitView {
            pagePanel
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
                .accessibilityIdentifier("compose.page-panel")
            VStack(spacing: 0) {
                bedCanvas
                    .accessibilityIdentifier("compose.bed-canvas")
                metricsBar
            }
            .frame(minWidth: 480)
            penLayerStudio
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
                .accessibilityIdentifier("compose.pen-layer-studio")
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Left: Page & content

    private var pagePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Page").font(.headline)

                if let msg = model.pageFitBlockingMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(msg, systemImage: "exclamationmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if let suggestion = model.suggestedLandscapeFormat {
                            let label = suggestion.id.contains("landscape")
                                ? "Use \(suggestion.name)"
                                : "Switch to \(suggestion.name)"
                            Button(label) {
                                model.setPageFormat(suggestion)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Choose a format that fits the \(Int(model.machine.travelX))×\(Int(model.machine.travelY)) mm bed.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }

                Picker("Format", selection: Binding(
                    get: { model.page.format.id },
                    set: { id in
                        if let format = PageFormat.presets.first(where: { $0.id == id }) {
                            model.setPageFormat(format)
                        }
                    }
                )) {
                    ForEach(PageFormat.presets) { format in
                        let fits = format.fits(on: model.machine)
                        Text("\(format.name) (\(Int(format.widthMm))×\(Int(format.heightMm)))\(fits ? "" : " — too large")")
                            .tag(format.id)
                    }
                }

                HStack {
                    labeled("Bed X", value: Binding(
                        get: { model.page.bedOriginX },
                        set: {
                            model.beginEditTransaction()
                            model.page.bedOriginX = $0
                            model.recomposePage()
                        }
                    ), onCommit: { model.endEditTransaction() })
                    labeled("Bed Y", value: Binding(
                        get: { model.page.bedOriginY },
                        set: {
                            model.beginEditTransaction()
                            model.page.bedOriginY = $0
                            model.recomposePage()
                        }
                    ), onCommit: { model.endEditTransaction() })
                }

                Picker("Coordinates", selection: Binding(
                    get: { model.page.editor.coordinateSpace },
                    set: { space in model.updatePageSetting { $0.editor.coordinateSpace = space } }
                )) {
                    Text("Paper").tag(CoordinateSpace.paper)
                    Text("Bed").tag(CoordinateSpace.bed)
                }
                .pickerStyle(.segmented)

                DisclosureGroup("Grid, rulers & snap", isExpanded: $showLayoutTools) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Show grid", isOn: Binding(
                            get: { model.page.editor.showGrid },
                            set: { v in model.updatePageSetting { $0.editor.showGrid = v } }
                        ))
                        Toggle("Snap to grid", isOn: Binding(
                            get: { model.page.editor.snapToGrid },
                            set: { v in model.updatePageSetting { $0.editor.snapToGrid = v } }
                        ))
                        Toggle("Snap to paper", isOn: Binding(
                            get: { model.page.editor.snapToPaper },
                            set: { v in model.updatePageSetting { $0.editor.snapToPaper = v } }
                        ))
                        Toggle("Snap to objects", isOn: Binding(
                            get: { model.page.editor.snapToObjects },
                            set: { v in model.updatePageSetting { $0.editor.snapToObjects = v } }
                        ))
                        labeled("Grid mm", value: Binding(
                            get: { model.page.editor.gridSpacingMm },
                            set: { v in model.updatePageSetting { $0.editor.gridSpacingMm = v } }
                        ))
                        labeled("Margin mm", value: Binding(
                            get: { model.page.editor.marginMm },
                            set: { v in model.updatePageSetting { $0.editor.marginMm = v } }
                        ))
                    }
                    .padding(.top, 4)
                }

                Divider()
                Text("Add content").font(.headline)
                ParagraphTextEditor(
                    label: "Paragraph text",
                    text: $model.newTextContent,
                    placeholder: "Type or paste a letter, address or paragraph…",
                    onCommandReturn: { model.addTextElement() }
                )
                .accessibilityIdentifier("compose.long-text-editor")
                HStack {
                    TextField("Size mm", value: $model.newTextHeight, format: .number)
                        .frame(width: 64)
                    Button("Add Paragraph") { model.addTextElement() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                HStack {
                    Button("Add SVG…") { openSVG() }
                    Button("Add Ink") { model.addInkToPage() }
                    Menu("Shape") {
                        Button("Rectangle") { model.addShape(.rect) }
                        Button("Rounded rect") { model.addShape(.roundedRect) }
                        Button("Circle") { model.addShape(.circle) }
                        Button("Ellipse") { model.addShape(.ellipse) }
                        Button("Line") { model.addShape(.line) }
                        Button("Polygon") { model.addShape(.polygon) }
                    }
                }

                if let id = model.selectedElementID,
                   let idx = model.page.elements.firstIndex(where: { $0.id == id }) {
                    selectedElementInspector(idx)
                        .accessibilityIdentifier("compose.selected-element-inspector")
                }

                Divider()
                batchSection
            }
            .padding(14)
        }
    }

    private func selectedElementInspector(_ idx: Int) -> some View {
        let el = model.page.elements[idx]
        let display = LayoutTools.displayPosition(element: el, page: model.page)
        let maxX = model.page.editor.coordinateSpace == .bed
            ? model.machine.travelX : model.page.format.widthMm
        let maxY = model.page.editor.coordinateSpace == .bed
            ? model.machine.travelY : model.page.format.heightMm

        return DisclosureGroup("Selected Element", isExpanded: $showSelectedInspector) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: Binding(
                    get: { model.page.elements[idx].name },
                    set: { model.renameSelected($0) }
                ))
                .onSubmit { model.commitRename() }
                Text(el.typeLabel).font(.caption).foregroundStyle(.secondary)

                sliderNumeric("X mm", value: Binding(
                    get: { display.x },
                    set: { model.updateSelectedGeometry(x: $0, y: display.y) }
                ), range: 0...maxX, onEditEnd: { model.endGeometryEdit() })
                sliderNumeric("Y mm", value: Binding(
                    get: { display.y },
                    set: { model.updateSelectedGeometry(x: display.x, y: $0) }
                ), range: 0...maxY, onEditEnd: { model.endGeometryEdit() })

                HStack {
                    labeled("W mm", value: Binding(
                        get: { model.page.elements[idx].widthMm },
                        set: { model.updateSelectedGeometry(width: $0) }
                    ))
                    labeled("H mm", value: Binding(
                        get: { model.page.elements[idx].heightMm },
                        set: { model.updateSelectedGeometry(height: $0) }
                    ))
                }
                Toggle("Lock aspect", isOn: Binding(
                    get: { model.page.elements[idx].lockAspect },
                    set: { model.updateSelectedGeometry(lockAspect: $0) }
                ))
                sliderNumeric("Rotation°", value: Binding(
                    get: { model.page.elements[idx].rotationDegrees },
                    set: { model.updateSelectedGeometry(rotation: $0) }
                ), range: -180...180, onEditEnd: { model.endGeometryEdit() })
                sliderNumeric("Scale %", value: Binding(
                    get: { model.page.elements[idx].scale * 100 },
                    set: { model.updateSelectedGeometry(scale: $0 / 100) }
                ), range: 10...400, onEditEnd: { model.endGeometryEdit() })

                Text("Anchor").font(.caption2).foregroundStyle(.secondary)
                AnchorPicker(selection: Binding(
                    get: { model.page.elements[idx].anchor },
                    set: { model.updateSelectedGeometry(anchor: $0) }
                ))

                HStack {
                    Button("Centre H") { model.centreSelected(horizontal: true, vertical: false) }
                    Button("Centre V") { model.centreSelected(horizontal: false, vertical: true) }
                }

                if case .textBox(let text, let style) = el.kind {
                    TextBoxEditor(
                        text: text,
                        style: style,
                        boxWidthMm: el.widthMm,
                        boxHeightMm: el.heightMm,
                        onChange: { t, s in model.updateTextBox(text: t, style: s) },
                        onEditingEnded: { model.endTextEditing() }
                    )
                }

                Picker("Layer", selection: Binding(
                    get: { model.page.elements[idx].layerID },
                    set: {
                        model.checkpointDocument()
                        model.page.elements[idx].layerID = $0
                        model.recomposePage()
                    }
                )) {
                    ForEach(model.page.layers) { layer in
                        Text(layer.name).tag(layer.id)
                    }
                }

                HStack {
                    Button("Duplicate") { model.duplicateSelectedElement() }
                    Button("Delete", role: .destructive) { model.deleteSelectedElement() }
                }
                HStack {
                    Button(el.locked ? "Unlock" : "Lock") { model.toggleLockSelected() }
                    Button(el.visible ? "Hide" : "Show") { model.toggleHideSelected() }
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Batch (variable data)").font(.headline)
            Text("Use `{name}`, `{address}`, `{table}`, `{message}` then import CSV.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Import CSV…") { model.importCSVForBatch() }
            if !model.batch.pages.isEmpty {
                Text("\(model.batch.pages.count) pages · \(model.batch.remainingCount) remaining")
                    .font(.caption)
                Button("Queue next page") { model.queueNextBatchPage() }
                ForEach(model.batch.pages.prefix(12)) { page in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("#\(page.index + 1)")
                                .font(.caption.monospaced())
                            Text(page.values["name"] ?? page.status.rawValue)
                                .font(.caption)
                                .lineLimit(1)
                            if page.overflows || page.status == .failed {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                            }
                            Spacer()
                            Button("Preview") { model.previewBatchPage(page.id) }
                                .font(.caption2)
                            Button("Skip") { model.skipBatchPage(page.id) }
                                .font(.caption2)
                        }
                        if let reason = page.errorMessage,
                           page.overflows || page.status == .failed || !page.missingFields.isEmpty {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Centre: bed canvas

    private var bedCanvas: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("-") { canvasZoom = max(0.4, canvasZoom - 0.1) }
                Button("100%") { canvasZoom = 1 }
                Button("+") { canvasZoom = min(3, canvasZoom + 0.1) }
                Toggle("Travel", isOn: $showTravelPaths)
                Spacer()
                if model.hasBlockingTextOverflow {
                    Text("Overflow blocks plotting")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            GeometryReader { geo in
                let bedW = model.machine.travelX
                let bedH = model.machine.travelY
                let scale = min(geo.size.width / bedW, geo.size.height / bedH) * 0.92 * canvasZoom
                let ox = (geo.size.width - bedW * scale) / 2
                let oy = (geo.size.height - bedH * scale) / 2

                ZStack(alignment: .topLeading) {
                    Color(nsColor: .controlBackgroundColor)

                    // Machine bed
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

                    if model.pageFitsBed {
                        paperAndPreview(ox: ox, oy: oy, scale: scale, bedH: bedH)
                    } else {
                        Text(model.pageFitBlockingMessage ?? "Page does not fit bed")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(16)
                            .position(x: ox + bedW * scale / 2, y: oy + bedH * scale / 2)
                    }

                    Text("Bed \(Int(bedW))×\(Int(bedH)) mm · \(model.page.format.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .gesture(dragGesture(ox: ox, oy: oy, scale: scale, bedH: bedH))
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func paperAndPreview(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some View {
        let page = model.page
        let px = ox + page.bedOriginX * scale
        let py = oy + (bedH - page.bedOriginY - page.format.heightMm) * scale
        let margin = page.editor.marginMm * scale

        // Paper (machine Y-up → view Y-down)
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: page.format.widthMm * scale, height: page.format.heightMm * scale)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5))
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

        if page.editor.showGrid {
            Path { path in
                var x = 0.0
                while x <= page.format.widthMm + 0.01 {
                    let sx = px + x * scale
                    path.move(to: CGPoint(x: sx, y: py))
                    path.addLine(to: CGPoint(x: sx, y: py + page.format.heightMm * scale))
                    x += page.editor.gridSpacingMm
                }
                var y = 0.0
                while y <= page.format.heightMm + 0.01 {
                    let sy = py + (page.format.heightMm - y) * scale
                    path.move(to: CGPoint(x: px, y: sy))
                    path.addLine(to: CGPoint(x: px + page.format.widthMm * scale, y: sy))
                    y += page.editor.gridSpacingMm
                }
            }
            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }

        ForEach(page.editor.guides) { guide in
            Path { path in
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
            .stroke(Color.cyan.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }

        // Selection frames (no SwiftUI rotationEffect — preview paths carry true orientation)
        ForEach(page.elements.filter(\.visible)) { el in
            let origin = el.frameOriginPaper
            let x = ox + (page.bedOriginX + origin.x) * scale
            let y = oy + (bedH - (page.bedOriginY + origin.y + el.heightMm * el.scale)) * scale
            let selected = model.selectedElementIDs.contains(el.id) || model.selectedElementID == el.id
            Rectangle()
                .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.2), lineWidth: selected ? 1.5 : 0.8)
                .background(Color.accentColor.opacity(selected ? 0.06 : 0.0))
                .frame(
                    width: max(el.widthMm * el.scale * scale, 4),
                    height: max(el.heightMm * el.scale * scale, 4)
                )
                .position(
                    x: x + el.widthMm * el.scale * scale / 2,
                    y: y + el.heightMm * el.scale * scale / 2
                )
                .onTapGesture {
                    model.selectElement(el.id, additive: NSEvent.modifierFlags.contains(.shift))
                }
        }

        if let job = model.previewJob {
            if showTravelPaths {
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

    private func dragGesture(ox: CGFloat, oy: CGFloat, scale: CGFloat, bedH: Double) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard model.pageFitsBed,
                      let id = model.selectedElementID,
                      let el = model.page.elements.first(where: { $0.id == id }),
                      !el.locked else { return }
                if !isDragging {
                    isDragging = true
                    model.beginDragGesture()
                }
                let paperX = (value.location.x - ox) / scale - model.page.bedOriginX
                let paperY = bedH - (value.location.y - oy) / scale - model.page.bedOriginY
                model.dragSelected(
                    toPaperX: paperX,
                    y: paperY,
                    disableSnap: NSEvent.modifierFlags.contains(.option)
                )
            }
            .onEnded { _ in
                isDragging = false
                model.endGeometryEdit()
            }
    }

    private var metricsBar: some View {
        HStack(spacing: 16) {
            Toggle("Optimize paths", isOn: $model.optimizePaths)
                .onChange(of: model.optimizePaths) { _ in model.recomposePage() }
            if let m = model.composedPage {
                metric("Draw", String(format: "%.0f mm", m.optimizedMetrics.drawDistanceMm))
                metric("Travel", String(format: "%.0f mm", m.optimizedMetrics.travelDistanceMm))
                metric("Pens", "\(m.optimizedMetrics.penChanges)")
                metric("ETA", m.optimizedMetrics.etaLabel)
                if m.hasBlockingOverflow {
                    Text("Overflow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if m.metrics.estimatedSeconds > m.optimizedMetrics.estimatedSeconds + 0.5 {
                    Text(String(
                        format: "saved %.0fs",
                        m.metrics.estimatedSeconds - m.optimizedMetrics.estimatedSeconds
                    ))
                    .font(.caption2)
                    .foregroundStyle(.green)
                }
            } else if !model.pageFitsBed {
                Text(model.pageFitBlockingMessage ?? "Page does not fit bed")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Add content to compose the page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Frame Page") { model.framePage() }
                .disabled(!model.canPreflightRun || !model.allowsManualCommands)
            Button("Preflight & Run") {
                model.applyPageToJob()
                if model.mode == .run,
                   model.composedPage != nil,
                   !model.hasBlockingTextOverflow,
                   model.pageFitsBed {
                    onPreflightRun?()
                }
            }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canPreflightRun)
                .accessibilityIdentifier("compose.preflight-run")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Right: Pen & Layer Studio

    private var penLayerStudio: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pen & Layer Studio").font(.headline)
                Spacer()
                Button("+") { model.addPenLayer() }
                Button("Duplicate") { model.duplicateSelectedLayer() }
                    .disabled(model.selectedLayerID == nil)
            }
            Toggle("Plot selected layer only", isOn: $model.plotOnlySelectedLayer)
                .onChange(of: model.plotOnlySelectedLayer) { _ in model.recomposePage() }
                .font(.caption)

            List(selection: $model.selectedLayerID) {
                ForEach(model.page.layers.sorted(by: { $0.order < $1.order })) { layer in
                    layerRow(layer)
                        .tag(layer.id)
                }
                .onMove(perform: moveLayers)
            }
            .listStyle(.inset)
            .frame(minHeight: 100)

            if let id = model.selectedLayerID,
               let idx = model.page.layers.firstIndex(where: { $0.id == id }) {
                Text("Preset").font(.subheadline.weight(.semibold))
                TextField("Name", text: Binding(
                    get: { model.page.layers[idx].name },
                    set: {
                        model.beginEditTransaction()
                        model.page.layers[idx].name = $0
                    }
                ))
                .onSubmit { model.endEditTransaction() }
                TextField("Colour #hex", text: Binding(
                    get: { model.page.layers[idx].pen.colorHex },
                    set: {
                        model.beginEditTransaction()
                        model.page.layers[idx].pen.colorHex = $0
                        model.recomposePage()
                    }
                ))
                .onSubmit { model.endEditTransaction() }
                HStack {
                    Text("Pressure")
                    Slider(
                        value: Binding(
                            get: { model.page.layers[idx].pen.pressure },
                            set: {
                                model.beginEditTransaction()
                                model.page.layers[idx].pen.pressure = $0
                                model.recomposePage()
                            }
                        ),
                        in: 0...1
                    ) { editing in
                        if !editing { model.endLayerSliderEdit() }
                    }
                }
                HStack {
                    labeled("Feed", value: Binding(
                        get: { model.page.layers[idx].pen.drawFeed },
                        set: {
                            model.beginEditTransaction()
                            model.page.layers[idx].pen.drawFeed = $0
                            model.recomposePage()
                        }
                    ), onCommit: { model.endEditTransaction() })
                    labeled("Passes", value: Binding(
                        get: { Double(model.page.layers[idx].pen.passes) },
                        set: {
                            model.beginEditTransaction()
                            model.page.layers[idx].pen.passes = max(1, Int($0))
                            model.recomposePage()
                        }
                    ), onCommit: { model.endEditTransaction() })
                }
                labeled("Lift delay ms", value: Binding(
                    get: { model.page.layers[idx].pen.liftDelayMs },
                    set: {
                        model.beginEditTransaction()
                        model.page.layers[idx].pen.liftDelayMs = $0
                        model.recomposePage()
                    }
                ), onCommit: { model.endEditTransaction() })
                Toggle("Pause before", isOn: Binding(
                    get: { model.page.layers[idx].pen.pauseBefore },
                    set: { v in model.updateLayer(id) { $0.pen.pauseBefore = v } }
                ))
                Toggle("Pause after", isOn: Binding(
                    get: { model.page.layers[idx].pen.pauseAfter },
                    set: { v in model.updateLayer(id) { $0.pen.pauseAfter = v } }
                ))
                Toggle("Visible", isOn: Binding(
                    get: { model.page.layers[idx].visible },
                    set: { v in model.updateLayer(id) { $0.visible = v } }
                ))
                Toggle("Locked", isOn: Binding(
                    get: { model.page.layers[idx].locked },
                    set: { v in model.updateLayer(id) { $0.locked = v } }
                ))
            }

            Text("Elements").font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.page.elements.sorted(by: { $0.zOrder > $1.zOrder })) { el in
                        elementRow(el)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func layerRow(_ layer: PageLayer) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: layer.pen.colorHex) ?? .primary)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.name)
                Text("\(layer.pen.name) · p\(String(format: "%.2f", layer.pen.pressure)) · ×\(layer.pen.passes)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: layer.visible ? "eye" : "eye.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if layer.locked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func elementRow(_ el: PageElement) -> some View {
        let warning: Bool = {
            if case .textBox(let text, let style) = el.kind {
                return TextLayoutEngine.layout(
                    text: text,
                    boxWidthMm: el.widthMm,
                    boxHeightMm: el.heightMm,
                    style: style
                ).overflows
            }
            return false
        }()
        return Button {
            model.selectElement(el.id, additive: NSEvent.modifierFlags.contains(.shift))
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: el.layerID))
                    .frame(width: 8, height: 8)
                Text(el.name).lineLimit(1)
                Spacer()
                if warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
                Image(systemName: el.visible ? "eye" : "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if el.locked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                (model.selectedElementID == el.id || model.selectedElementIDs.contains(el.id))
                    ? Color.accentColor.opacity(0.12) : .clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Bring to Front") { model.reorderSelected(action: LayoutTools.bringToFront) }
            Button("Send to Back") { model.reorderSelected(action: LayoutTools.sendToBack) }
            Button(el.locked ? "Unlock" : "Lock") { model.toggleLockSelected() }
            Button(el.visible ? "Hide" : "Show") { model.toggleHideSelected() }
            Button("Duplicate") { model.duplicateSelectedElement() }
            Button("Delete", role: .destructive) { model.deleteSelectedElement() }
        }
    }

    private func moveLayers(from: IndexSet, to: Int) {
        model.beginEditTransaction()
        var layers = model.page.layers.sorted { $0.order < $1.order }
        layers.move(fromOffsets: from, toOffset: to)
        for (i, _) in layers.enumerated() { layers[i].order = i }
        model.page.layers = layers
        model.endEditTransaction()
        model.recomposePage()
    }

    // MARK: - Helpers

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced())
        }
    }

    private func labeled(
        _ title: String,
        value: Binding<Double>,
        onCommit: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .onSubmit { onCommit?() }
        }
    }

    private func sliderNumeric(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        onEditEnd: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: 0.1) { editing in
                    if !editing { onEditEnd?() }
                }
                TextField("", value: value, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .onSubmit { onEditEnd?() }
            }
        }
    }

    private func color(for layerID: UUID) -> Color {
        Color(hex: model.page.layer(for: layerID)?.pen.colorHex ?? "#333333") ?? .accentColor
    }

    private func openSVG() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        if panel.runModal() == .OK, let url = panel.url {
            model.addSVGToPage(url: url)
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
            case 51, 117: model.deleteSelectedElement(); return nil
            default:
                if flags.contains(.command) {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "z" where flags.contains(.shift): model.redoDocument(); return nil
                    case "z": model.undoDocument(); return nil
                    case "c": model.copySelectedElements(); return nil
                    case "v": model.pasteClipboardElements(); return nil
                    case "d": model.duplicateSelectedElement(); return nil
                    default: break
                    }
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - Shared helpers (used only by the canonical Compose UI)

struct AnchorPicker: View {
    @Binding var selection: PageAnchor

    private let rows: [[PageAnchor]] = [
        [.topLeft, .topCenter, .topRight],
        [.centerLeft, .center, .centerRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { point in
                        Button { selection = point } label: {
                            Circle()
                                .fill(selection == point ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .help(point.label)
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
