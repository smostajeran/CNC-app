import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CNCCore

/// Persistent millimetre inspector: sliders + exact numeric fields, anchors, text box.
struct PrecisionInspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                projectBar
                pageSection
                addContentSection
                if let id = model.selectedElementID,
                   let idx = model.page.elements.firstIndex(where: { $0.id == id }) {
                    elementSection(idx)
                }
                batchSection
            }
            .padding(14)
        }
    }

    private var projectBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project").font(.headline)
            HStack {
                Button("Open") { model.openProject() }
                Button("Save") { model.saveProject() }
                Button("Save As") {
                    model.projectURL = nil
                    model.saveProject()
                }
            }
            HStack {
                Button("Undo") { model.undoDocument() }.disabled(!model.canUndo)
                Button("Redo") { model.redoDocument() }.disabled(!model.canRedo)
                Spacer()
                Button("Export SVG") { model.exportComposedSVG() }
                    .disabled(model.composedPage == nil)
            }
            .font(.caption)
        }
    }

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            sliderNumeric("Bed X", value: Binding(
                get: { model.page.bedOriginX },
                set: {
                    model.beginEditTransaction()
                    model.page.bedOriginX = $0
                    model.recomposePage()
                }
            ), range: 0...model.machine.travelX, step: 0.1, onEditEnd: { model.endEditTransaction() })
            sliderNumeric("Bed Y", value: Binding(
                get: { model.page.bedOriginY },
                set: {
                    model.beginEditTransaction()
                    model.page.bedOriginY = $0
                    model.recomposePage()
                }
            ), range: 0...model.machine.travelY, step: 0.1, onEditEnd: { model.endEditTransaction() })
            Picker("Coordinates", selection: Binding(
                get: { model.page.editor.coordinateSpace },
                set: { space in model.updatePageSetting { $0.editor.coordinateSpace = space } }
            )) {
                Text("Paper").tag(CoordinateSpace.paper)
                Text("Bed").tag(CoordinateSpace.bed)
            }
            .pickerStyle(.segmented)
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
    }

    private var addContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add content").font(.headline)
            TextEditor(text: $model.newTextContent)
                .frame(minHeight: 64, maxHeight: 120)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
            HStack {
                TextField("Size mm", value: $model.newTextHeight, format: .number)
                    .frame(width: 64)
                Button("Add paragraph") { model.addTextElement() }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Button("SVG…") { openSVG() }
                Button("Ink") { model.addInkToPage() }
                Menu("Shape") {
                    Button("Rectangle") { model.addShape(.rect) }
                    Button("Rounded rect") { model.addShape(.roundedRect) }
                    Button("Circle") { model.addShape(.circle) }
                    Button("Ellipse") { model.addShape(.ellipse) }
                    Button("Line") { model.addShape(.line) }
                    Button("Polygon") { model.addShape(.polygon) }
                }
            }
        }
    }

    private func elementSection(_ idx: Int) -> some View {
        let el = model.page.elements[idx]
        let display = LayoutTools.displayPosition(element: el, page: model.page)
        let maxX = model.page.editor.coordinateSpace == .bed
            ? model.machine.travelX
            : model.page.format.widthMm
        let maxY = model.page.editor.coordinateSpace == .bed
            ? model.machine.travelY
            : model.page.format.heightMm

        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            TextField("Name", text: Binding(
                get: { model.page.elements[idx].name },
                set: { model.renameSelected($0) }
            ))
            .onSubmit { model.commitRename() }
            Text(el.typeLabel).font(.caption).foregroundStyle(.secondary)

            sliderNumeric("X mm", value: Binding(
                get: { display.x },
                set: { model.updateSelectedGeometry(x: $0, y: display.y) }
            ), range: 0...maxX, step: 0.1, onEditEnd: { model.endGeometryEdit() })
            sliderNumeric("Y mm", value: Binding(
                get: { display.y },
                set: { model.updateSelectedGeometry(x: display.x, y: $0) }
            ), range: 0...maxY, step: 0.1, onEditEnd: { model.endGeometryEdit() })

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
            ), range: -180...180, step: 0.1, onEditEnd: { model.endGeometryEdit() })
            sliderNumeric("Scale %", value: Binding(
                get: { model.page.elements[idx].scale * 100 },
                set: { model.updateSelectedGeometry(scale: $0 / 100) }
            ), range: 10...400, step: 1, onEditEnd: { model.endGeometryEdit() })

            Text("Anchor").font(.caption).foregroundStyle(.secondary)
            AnchorPicker(selection: Binding(
                get: { model.page.elements[idx].anchor },
                set: { model.updateSelectedGeometry(anchor: $0) }
            ))

            HStack {
                Button("Centre H") { model.centreSelected(horizontal: true, vertical: false) }
                Button("Centre V") { model.centreSelected(horizontal: false, vertical: true) }
            }
            HStack {
                Button("Reset rot") { model.updateSelectedGeometry(rotation: 0) }
                Button("Reset scale") { model.updateSelectedGeometry(scale: 1) }
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
            HStack {
                Button("Front") { model.reorderSelected(action: LayoutTools.bringToFront) }
                Button("Forward") { model.reorderSelected(action: LayoutTools.bringForward) }
                Button("Backward") { model.reorderSelected(action: LayoutTools.sendBackward) }
                Button("Back") { model.reorderSelected(action: LayoutTools.sendToBack) }
            }
            .font(.caption)
        }
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Batch").font(.headline)
            Text("Placeholders: {name}, {address}, {table}, {message}")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Import CSV…") { model.importCSVForBatch() }
            if !model.batch.pages.isEmpty {
                Text("\(model.batch.pages.count) records · \(model.batch.remainingCount) remaining")
                    .font(.caption)
                Button("Queue next page") { model.queueNextBatchPage() }
                    .buttonStyle(.borderedProminent)
                ForEach(model.batch.pages.prefix(16)) { page in
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
                            if !page.missingFields.isEmpty {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption2)
                            }
                            Spacer()
                            Button("Preview") { model.previewBatchPage(page.id) }
                                .font(.caption2)
                            Button("Skip") { model.skipBatchPage(page.id) }
                                .font(.caption2)
                        }
                        if let reason = page.errorMessage, page.overflows || page.status == .failed || !page.missingFields.isEmpty {
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

    private func sliderNumeric(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
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
                Slider(value: value, in: range, step: step) { editing in
                    if !editing { onEditEnd?() }
                }
                TextField("", value: value, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .onSubmit { onEditEnd?() }
            }
        }
    }

    private func labeled(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
        }
    }

    private func openSVG() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        if panel.runModal() == .OK, let url = panel.url {
            model.addSVGToPage(url: url)
        }
    }
}

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
                        Button {
                            selection = point
                        } label: {
                            Circle()
                                .fill(selection == point ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 16, height: 16)
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
