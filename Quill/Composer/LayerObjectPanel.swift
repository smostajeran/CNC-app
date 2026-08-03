import SwiftUI
import AppKit
import CNCCore

/// Persistent object / layer panel with pens, visibility, lock, and plot order.
struct LayerObjectPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layers").font(.headline)
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
            .frame(minHeight: 120)

            if let id = model.selectedLayerID,
               let idx = model.page.layers.firstIndex(where: { $0.id == id }) {
                layerInspector(idx)
            }

            Text("Objects").font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.page.elements.sorted(by: { $0.zOrder > $1.zOrder })) { el in
                        objectRow(el)
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

    private func layerInspector(_ idx: Int) -> some View {
        let layerID = model.page.layers[idx].id
        return VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: Binding(
                get: { model.page.layers[idx].name },
                set: { name in
                    model.beginEditTransaction()
                    model.page.layers[idx].name = name
                }
            ))
            .onSubmit { model.endEditTransaction() }
            TextField("Colour #hex", text: Binding(
                get: { model.page.layers[idx].pen.colorHex },
                set: { hex in
                    model.beginEditTransaction()
                    model.page.layers[idx].pen.colorHex = hex
                    model.recomposePage()
                }
            ))
            .onSubmit { model.endEditTransaction() }
            HStack {
                Text("Pressure")
                Slider(
                    value: Binding(
                        get: { model.page.layers[idx].pen.pressure },
                        set: { value in
                            model.beginEditTransaction()
                            model.page.layers[idx].pen.pressure = value
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
                    set: { value in
                        model.beginEditTransaction()
                        model.page.layers[idx].pen.drawFeed = value
                        model.recomposePage()
                    }
                ))
                labeled("Passes", value: Binding(
                    get: { Double(model.page.layers[idx].pen.passes) },
                    set: { value in
                        model.beginEditTransaction()
                        model.page.layers[idx].pen.passes = max(1, Int(value))
                        model.recomposePage()
                    }
                ))
            }
            labeled("Lift delay ms", value: Binding(
                get: { model.page.layers[idx].pen.liftDelayMs },
                set: { value in
                    model.beginEditTransaction()
                    model.page.layers[idx].pen.liftDelayMs = value
                    model.recomposePage()
                }
            ))
            Toggle("Pause before", isOn: Binding(
                get: { model.page.layers[idx].pen.pauseBefore },
                set: { value in
                    model.updateLayer(layerID) { $0.pen.pauseBefore = value }
                }
            ))
            Toggle("Pause after", isOn: Binding(
                get: { model.page.layers[idx].pen.pauseAfter },
                set: { value in
                    model.updateLayer(layerID) { $0.pen.pauseAfter = value }
                }
            ))
            Toggle("Visible", isOn: Binding(
                get: { model.page.layers[idx].visible },
                set: { value in
                    model.updateLayer(layerID) { $0.visible = value }
                }
            ))
            Toggle("Locked", isOn: Binding(
                get: { model.page.layers[idx].locked },
                set: { value in
                    model.updateLayer(layerID) { $0.locked = value }
                }
            ))
            if let m = model.composedPage {
                Text(String(
                    format: "Draw %.0f mm · Travel %.0f mm · %@",
                    m.optimizedMetrics.drawDistanceMm,
                    m.optimizedMetrics.travelDistanceMm,
                    m.optimizedMetrics.etaLabel
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func objectRow(_ el: PageElement) -> some View {
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
                    .fill(Color(hex: model.page.layer(for: el.layerID)?.pen.colorHex ?? "#333333") ?? .accentColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(el.name).lineLimit(1)
                    Text("\(el.typeLabel) · z\(el.zOrder)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                (model.selectedElementID == el.id || model.selectedElementIDs.contains(el.id))
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: el.id.uuidString as NSString)
        }
    }

    private func moveLayers(from: IndexSet, to: Int) {
        model.beginEditTransaction()
        var layers = model.page.layers.sorted { $0.order < $1.order }
        layers.move(fromOffsets: from, toOffset: to)
        for (i, _) in layers.enumerated() {
            layers[i].order = i
        }
        model.page.layers = layers
        model.endEditTransaction()
        model.recomposePage()
    }

    private func labeled(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
        }
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
