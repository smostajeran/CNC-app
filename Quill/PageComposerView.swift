import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

/// True-size page on the machine bed with layers, metrics, and batch queue.
struct PageComposerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            inspector
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
            VStack(spacing: 0) {
                bedCanvas
                metricsBar
            }
            .frame(minWidth: 480)
            layerStudio
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        }
    }

    // MARK: - Left inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Page").font(.headline)
                Picker("Format", selection: Binding(
                    get: { model.page.format.id },
                    set: { id in
                        if let format = PageFormat.presets.first(where: { $0.id == id }) {
                            model.setPageFormat(format)
                        }
                    }
                )) {
                    ForEach(PageFormat.presets) { format in
                        Text("\(format.name) (\(Int(format.widthMm))×\(Int(format.heightMm)))")
                            .tag(format.id)
                    }
                }

                HStack {
                    labeled("Bed X", value: $model.page.bedOriginX)
                    labeled("Bed Y", value: $model.page.bedOriginY)
                }
                .onChange(of: model.page.bedOriginX) { _ in model.recomposePage() }
                .onChange(of: model.page.bedOriginY) { _ in model.recomposePage() }

                Divider()
                Text("Add content").font(.headline)
                HStack {
                    TextField("Text", text: $model.newTextContent)
                    TextField("mm", value: $model.newTextHeight, format: .number)
                        .frame(width: 44)
                    Button("Add") { model.addTextElement() }
                }
                HStack {
                    Button("Add SVG…") { openSVG() }
                    Button("Add ink") { model.addInkToPage() }
                }

                if let id = model.selectedElementID,
                   let idx = model.page.elements.firstIndex(where: { $0.id == id }) {
                    Divider()
                    Text("Selected: \(model.page.elements[idx].name)").font(.headline)
                    HStack {
                        labeled("X", value: $model.page.elements[idx].xMm)
                        labeled("Y", value: $model.page.elements[idx].yMm)
                    }
                    HStack {
                        labeled("Rot°", value: $model.page.elements[idx].rotationDegrees)
                        labeled("Scale", value: $model.page.elements[idx].scale)
                    }
                    .onChange(of: model.page.elements[idx].xMm) { _ in model.recomposePage() }
                    .onChange(of: model.page.elements[idx].yMm) { _ in model.recomposePage() }
                    .onChange(of: model.page.elements[idx].rotationDegrees) { _ in model.recomposePage() }
                    .onChange(of: model.page.elements[idx].scale) { _ in model.recomposePage() }

                    Picker("Layer", selection: $model.page.elements[idx].layerID) {
                        ForEach(model.page.layers) { layer in
                            Text(layer.name).tag(layer.id)
                        }
                    }
                    .onChange(of: model.page.elements[idx].layerID) { _ in model.recomposePage() }

                    HStack {
                        Button("Duplicate") { model.duplicateSelectedElement() }
                        Button("Delete", role: .destructive) { model.deleteSelectedElement() }
                    }
                }

                Divider()
                Text("Batch (variable data)").font(.headline)
                Text("Use `{name}` in text elements, then import CSV.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Import CSV…") { model.importCSVForBatch() }
                if !model.batch.pages.isEmpty {
                    Text("\(model.batch.pages.count) pages · \(model.batch.remainingCount) remaining")
                        .font(.caption)
                    Button("Queue next page") { model.queueNextBatchPage() }
                        .buttonStyle(.borderedProminent)
                    ForEach(model.batch.pages.prefix(12)) { page in
                        HStack {
                            Text("#\(page.index + 1)")
                                .font(.caption.monospaced())
                            Text(page.values["name"] ?? page.status.rawValue)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button("Preview") { model.previewBatchPage(page.id) }
                                .font(.caption2)
                            Button("Skip") { model.skipBatchPage(page.id) }
                                .font(.caption2)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Bed canvas

    private var bedCanvas: some View {
        GeometryReader { geo in
            let bedW = model.machine.travelX
            let bedH = model.machine.travelY
            let scale = min(geo.size.width / bedW, geo.size.height / bedH) * 0.92
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
                    .overlay(
                        Rectangle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .position(x: ox + bedW * scale / 2, y: oy + bedH * scale / 2)

                // Paper
                let page = model.page
                let px = ox + page.bedOriginX * scale
                let py = oy + (bedH - page.bedOriginY - page.format.heightMm) * scale
                Rectangle()
                    .fill(Color.white)
                    .frame(width: page.format.widthMm * scale, height: page.format.heightMm * scale)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .overlay(
                        Rectangle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    )
                    .position(
                        x: px + page.format.widthMm * scale / 2,
                        y: py + page.format.heightMm * scale / 2
                    )

                // Preview paths in machine space
                if let job = model.previewJob {
                    Path { path in
                        var started = false
                        for cmd in job.commands {
                            switch cmd {
                            case .move(let p):
                                let pt = CGPoint(
                                    x: ox + p.x * scale,
                                    y: oy + (bedH - p.y) * scale
                                )
                                path.move(to: pt)
                                started = true
                            case .line(let p):
                                let pt = CGPoint(
                                    x: ox + p.x * scale,
                                    y: oy + (bedH - p.y) * scale
                                )
                                if started {
                                    path.addLine(to: pt)
                                } else {
                                    path.move(to: pt)
                                    started = true
                                }
                            case .penChange:
                                started = false
                            }
                        }
                    }
                    .stroke(Color.accentColor, lineWidth: 1.2)
                }

                Text("Bed \(Int(bedW))×\(Int(bedH)) mm · \(page.format.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .padding(8)
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
                if m.metrics.estimatedSeconds > m.optimizedMetrics.estimatedSeconds + 0.5 {
                    Text(String(
                        format: "saved %.0fs",
                        m.metrics.estimatedSeconds - m.optimizedMetrics.estimatedSeconds
                    ))
                    .font(.caption2)
                    .foregroundStyle(.green)
                }
            } else {
                Text("Add content to compose the page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Frame Page") { model.framePage() }
                .disabled(model.composedPage == nil || !model.allowsManualCommands)
            Button("Preflight & Run") { model.applyPageToJob() }
                .buttonStyle(.borderedProminent)
                .disabled(model.composedPage == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Layer studio

    private var layerStudio: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pen & Layer Studio").font(.headline)
                Spacer()
                Button("+") { model.addPenLayer() }
            }
            List(selection: $model.selectedLayerID) {
                ForEach(model.page.layers.sorted(by: { $0.order < $1.order })) { layer in
                    layerRow(layer)
                        .tag(layer.id)
                }
                .onMove(perform: moveLayers)
            }
            .listStyle(.inset)

            if let id = model.selectedLayerID,
               let idx = model.page.layers.firstIndex(where: { $0.id == id }) {
                Text("Preset").font(.subheadline.weight(.semibold))
                TextField("Name", text: $model.page.layers[idx].name)
                TextField("Colour #hex", text: $model.page.layers[idx].pen.colorHex)
                HStack {
                    Text("Pressure")
                    Slider(value: $model.page.layers[idx].pen.pressure, in: 0...1)
                }
                HStack {
                    labeled("Feed", value: $model.page.layers[idx].pen.drawFeed)
                    labeled("Passes", value: Binding(
                        get: { Double(model.page.layers[idx].pen.passes) },
                        set: { model.page.layers[idx].pen.passes = max(1, Int($0)) }
                    ))
                }
                labeled("Lift delay ms", value: $model.page.layers[idx].pen.liftDelayMs)
                    .onChange(of: model.page.layers[idx].pen) { _ in model.recomposePage() }
            }

            Text("Elements").font(.subheadline.weight(.semibold))
            ForEach(model.page.elements) { el in
                Button {
                    model.selectedElementID = el.id
                } label: {
                    HStack {
                        Circle()
                            .fill(color(for: el.layerID))
                            .frame(width: 8, height: 8)
                        Text(el.name)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .background(model.selectedElementID == el.id ? Color.accentColor.opacity(0.12) : .clear)
            }
            Spacer()
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
        }
    }

    private func moveLayers(from: IndexSet, to: Int) {
        var layers = model.page.layers.sorted { $0.order < $1.order }
        layers.move(fromOffsets: from, toOffset: to)
        for (i, _) in layers.enumerated() {
            layers[i].order = i
        }
        model.page.layers = layers
        model.recomposePage()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced())
        }
    }

    private func labeled(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
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
}

private extension Color {
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
