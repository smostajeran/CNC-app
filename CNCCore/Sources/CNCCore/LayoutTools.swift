import Foundation

/// Alignment, distribution, z-order, and coordinate helpers for the page editor.
public enum LayoutTools {
    public static func align(
        _ elements: inout [PageElement],
        ids: [UUID],
        page: PageDocument,
        horizontal: TextAlignment? = nil,
        vertical: VerticalAlign? = nil
    ) {
        guard !ids.isEmpty else { return }
        let selected = elements.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }

        if let horizontal {
            let target: Double
            switch horizontal {
            case .left:
                target = selected.map { $0.frameOriginPaper.x }.min() ?? 0
                for i in elements.indices where ids.contains(elements[i].id) {
                    let origin = elements[i].frameOriginPaper
                    let dx = target - origin.x
                    elements[i].xMm += dx
                }
            case .center:
                let minX = selected.map { $0.frameOriginPaper.x }.min() ?? 0
                let maxX = selected.map { $0.frameOriginPaper.x + $0.widthMm * $0.scale }.max() ?? 0
                let mid = (minX + maxX) / 2
                for i in elements.indices where ids.contains(elements[i].id) {
                    let origin = elements[i].frameOriginPaper
                    let cx = origin.x + elements[i].widthMm * elements[i].scale / 2
                    elements[i].xMm += mid - cx
                }
            case .right:
                let target = selected.map { $0.frameOriginPaper.x + $0.widthMm * $0.scale }.max() ?? 0
                for i in elements.indices where ids.contains(elements[i].id) {
                    let origin = elements[i].frameOriginPaper
                    let right = origin.x + elements[i].widthMm * elements[i].scale
                    elements[i].xMm += target - right
                }
            }
        }

        if let vertical {
            switch vertical {
            case .top:
                let target = selected.map { $0.frameOriginPaper.y + $0.heightMm * $0.scale }.max() ?? 0
                for i in elements.indices where ids.contains(elements[i].id) {
                    let top = elements[i].frameOriginPaper.y + elements[i].heightMm * elements[i].scale
                    elements[i].yMm += target - top
                }
            case .middle:
                let minY = selected.map { $0.frameOriginPaper.y }.min() ?? 0
                let maxY = selected.map { $0.frameOriginPaper.y + $0.heightMm * $0.scale }.max() ?? 0
                let mid = (minY + maxY) / 2
                for i in elements.indices where ids.contains(elements[i].id) {
                    let origin = elements[i].frameOriginPaper
                    let cy = origin.y + elements[i].heightMm * elements[i].scale / 2
                    elements[i].yMm += mid - cy
                }
            case .bottom:
                let target = selected.map { $0.frameOriginPaper.y }.min() ?? 0
                for i in elements.indices where ids.contains(elements[i].id) {
                    let origin = elements[i].frameOriginPaper
                    elements[i].yMm += target - origin.y
                }
            }
        }
        _ = page
    }

    public enum VerticalAlign: String, Sendable {
        case top, middle, bottom
    }

    public static func centreOnPage(_ element: inout PageElement, page: PageDocument, horizontal: Bool, vertical: Bool) {
        let w = element.widthMm * element.scale
        let h = element.heightMm * element.scale
        let f = element.anchor.fractions
        if horizontal {
            element.xMm = page.format.widthMm / 2 - w / 2 + f.x * w
        }
        if vertical {
            element.yMm = page.format.heightMm / 2 - h / 2 + f.y * h
        }
    }

    public static func distribute(
        _ elements: inout [PageElement],
        ids: [UUID],
        horizontal: Bool
    ) {
        let idxs = elements.indices.filter { ids.contains(elements[$0].id) }
        guard idxs.count >= 3 else { return }
        if horizontal {
            let sorted = idxs.sorted {
                elements[$0].frameOriginPaper.x < elements[$1].frameOriginPaper.x
            }
            let first = elements[sorted.first!].frameOriginPaper.x
            let lastEl = elements[sorted.last!]
            let last = lastEl.frameOriginPaper.x + lastEl.widthMm * lastEl.scale
            let totalW = sorted.dropFirst().dropLast().reduce(0.0) {
                $0 + elements[$1].widthMm * elements[$1].scale
            }
            let gap = (last - first - (elements[sorted.first!].widthMm * elements[sorted.first!].scale) - totalW
                - lastEl.widthMm * lastEl.scale) / Double(sorted.count - 1)
            var cursor = first + elements[sorted.first!].widthMm * elements[sorted.first!].scale + gap
            for i in sorted.dropFirst().dropLast() {
                let origin = elements[i].frameOriginPaper
                let dx = cursor - origin.x
                elements[i].xMm += dx
                cursor += elements[i].widthMm * elements[i].scale + gap
            }
        } else {
            let sorted = idxs.sorted {
                elements[$0].frameOriginPaper.y < elements[$1].frameOriginPaper.y
            }
            let first = elements[sorted.first!].frameOriginPaper.y
            let lastEl = elements[sorted.last!]
            let last = lastEl.frameOriginPaper.y + lastEl.heightMm * lastEl.scale
            let totalH = sorted.dropFirst().dropLast().reduce(0.0) {
                $0 + elements[$1].heightMm * elements[$1].scale
            }
            let gap = (last - first - (elements[sorted.first!].heightMm * elements[sorted.first!].scale) - totalH
                - lastEl.heightMm * lastEl.scale) / Double(sorted.count - 1)
            var cursor = first + elements[sorted.first!].heightMm * elements[sorted.first!].scale + gap
            for i in sorted.dropFirst().dropLast() {
                let origin = elements[i].frameOriginPaper
                let dy = cursor - origin.y
                elements[i].yMm += dy
                cursor += elements[i].heightMm * elements[i].scale + gap
            }
        }
    }

    public static func bringForward(_ elements: inout [PageElement], id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        let z = elements[i].zOrder
        if let j = elements.indices.filter({ elements[$0].zOrder > z }).min(by: { elements[$0].zOrder < elements[$1].zOrder }) {
            let other = elements[j].zOrder
            elements[j].zOrder = z
            elements[i].zOrder = other
        }
    }

    public static func sendBackward(_ elements: inout [PageElement], id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        let z = elements[i].zOrder
        if let j = elements.indices.filter({ elements[$0].zOrder < z }).max(by: { elements[$0].zOrder < elements[$1].zOrder }) {
            let other = elements[j].zOrder
            elements[j].zOrder = z
            elements[i].zOrder = other
        }
    }

    public static func bringToFront(_ elements: inout [PageElement], id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[i].zOrder = (elements.map(\.zOrder).max() ?? 0) + 1
    }

    public static func sendToBack(_ elements: inout [PageElement], id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[i].zOrder = (elements.map(\.zOrder).min() ?? 0) - 1
    }

    /// Display coordinates for inspector (paper or bed).
    public static func displayPosition(element: PageElement, page: PageDocument) -> (x: Double, y: Double) {
        switch page.editor.coordinateSpace {
        case .paper:
            return (element.xMm, element.yMm)
        case .bed:
            let bed = page.paperToBed(x: element.xMm, y: element.yMm)
            return bed
        }
    }

    public static func setDisplayPosition(element: inout PageElement, page: PageDocument, x: Double, y: Double) {
        switch page.editor.coordinateSpace {
        case .paper:
            element.xMm = x
            element.yMm = y
        case .bed:
            let paper = page.bedToPaper(x: x, y: y)
            element.xMm = paper.x
            element.yMm = paper.y
        }
    }
}
