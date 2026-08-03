import Foundation

/// One generated page in a variable-data batch.
public struct BatchPage: Equatable, Sendable, Codable, Identifiable {
    public enum Status: String, Equatable, Sendable, Codable {
        case pending
        case ready
        case plotting
        case pausedForPaper
        case completed
        case skipped
        case failed
    }

    public var id: UUID
    public var index: Int
    public var values: [String: String]
    public var status: Status
    public var errorMessage: String?
    public var overflows: Bool
    public var missingFields: [String]
    public var copies: Int

    public init(
        id: UUID = UUID(),
        index: Int,
        values: [String: String],
        status: Status = .pending,
        errorMessage: String? = nil,
        overflows: Bool = false,
        missingFields: [String] = [],
        copies: Int = 1
    ) {
        self.id = id
        self.index = index
        self.values = values
        self.status = status
        self.errorMessage = errorMessage
        self.overflows = overflows
        self.missingFields = missingFields
        self.copies = max(1, copies)
    }
}

public struct BatchDocument: Equatable, Sendable, Codable {
    public var template: PageDocument
    /// Element id → template string with `{field}` placeholders.
    public var fieldMap: [UUID: String]
    public var pages: [BatchPage]
    public var pauseBetweenPages: Bool
    public var pageChangeDelaySeconds: Double
    public var currentIndex: Int

    public init(
        template: PageDocument = PageDocument(),
        fieldMap: [UUID: String] = [:],
        pages: [BatchPage] = [],
        pauseBetweenPages: Bool = true,
        pageChangeDelaySeconds: Double = 0,
        currentIndex: Int = 0
    ) {
        self.template = template
        self.fieldMap = fieldMap
        self.pages = pages
        self.pauseBetweenPages = pauseBetweenPages
        self.pageChangeDelaySeconds = max(0, pageChangeDelaySeconds)
        self.currentIndex = currentIndex
    }

    public var remainingCount: Int {
        pages.filter { $0.status == .pending || $0.status == .ready || $0.status == .pausedForPaper }.count
    }
}

public enum VariableData {
    /// Minimal CSV parser (comma-separated, optional header row).
    public static func parseCSV(_ text: String) -> (headers: [String], rows: [[String: String]]) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return ([], []) }
        let headers = splitCSVLine(headerLine)
        var rows: [[String: String]] = []
        for line in lines.dropFirst() {
            let cols = splitCSVLine(line)
            var row: [String: String] = [:]
            for (i, h) in headers.enumerated() {
                row[h] = i < cols.count ? cols[i] : ""
            }
            rows.append(row)
        }
        return (headers, rows)
    }

    public static func makeBatch(
        template: PageDocument,
        fieldMap: [UUID: String],
        rows: [[String: String]],
        pauseBetweenPages: Bool = true
    ) -> BatchDocument {
        let pages = rows.enumerated().map { idx, row in
            BatchPage(index: idx, values: row, status: .ready)
        }
        var batch = BatchDocument(
            template: template,
            fieldMap: fieldMap,
            pages: pages,
            pauseBetweenPages: pauseBetweenPages
        )
        batch.pages = validateRecords(batch: batch)
        return batch
    }

    /// Substitute `{field}` tokens in a template string.
    public static func apply(_ template: String, values: [String: String]) -> String {
        var out = template
        for (key, value) in values {
            out = out.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return out
    }

    /// Materialize one batch page into a concrete PageDocument (text elements expanded).
    public static func materialize(batch: BatchDocument, pageID: UUID) -> PageDocument? {
        guard let page = batch.pages.first(where: { $0.id == pageID }) else { return nil }
        var doc = batch.template
        doc.name = "\(batch.template.name) #\(page.index + 1)"
        doc.elements = doc.elements.map { el in
            var copy = el
            if let tmpl = batch.fieldMap[el.id] {
                let text = apply(tmpl, values: page.values)
                applyText(&copy, text: text)
            } else {
                switch el.kind {
                case .text(let raw, let height) where raw.contains("{"):
                    copy.kind = .text(apply(raw, values: page.values), heightMm: height)
                case .textBox(let raw, let style) where raw.contains("{"):
                    copy.kind = .textBox(text: apply(raw, values: page.values), style: style)
                default:
                    break
                }
            }
            return copy
        }
        return doc
    }

    /// Validate overflow and missing `{fields}` independently for every CSV record.
    public static func validateRecords(batch: BatchDocument) -> [BatchPage] {
        batch.pages.map { page in
            var updated = page
            let placeholders = collectPlaceholders(batch: batch)
            updated.missingFields = placeholders.filter { key in
                let value = page.values[key] ?? ""
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            updated.overflows = false
            updated.errorMessage = nil
            if let material = materialize(batch: batch, pageID: page.id) {
                for el in material.elements {
                    if case .textBox(let text, let style) = el.kind {
                        let layout = TextLayoutEngine.layout(
                            text: text,
                            boxWidthMm: el.widthMm,
                            boxHeightMm: el.heightMm,
                            style: style
                        )
                        if layout.overflows {
                            updated.overflows = true
                            updated.errorMessage = layout.overflowMessage
                        }
                    }
                }
            }
            if !updated.missingFields.isEmpty {
                let miss = "Missing fields: \(updated.missingFields.joined(separator: ", "))"
                updated.errorMessage = updated.errorMessage.map { $0 + " · " + miss } ?? miss
            }
            return updated
        }
    }

    public static func collectPlaceholders(batch: BatchDocument) -> [String] {
        var keys = Set<String>()
        for tmpl in batch.fieldMap.values {
            keys.formUnion(placeholderNames(in: tmpl))
        }
        for el in batch.template.elements {
            switch el.kind {
            case .text(let raw, _):
                keys.formUnion(placeholderNames(in: raw))
            case .textBox(let raw, _):
                keys.formUnion(placeholderNames(in: raw))
            default:
                break
            }
        }
        return keys.sorted()
    }

    public static func placeholderNames(in template: String) -> [String] {
        var names: [String] = []
        var remaining = template[...]
        while let open = remaining.firstIndex(of: "{"),
              let close = remaining[open...].firstIndex(of: "}") {
            let start = remaining.index(after: open)
            if start < close {
                names.append(String(remaining[start..<close]))
            }
            remaining = remaining[remaining.index(after: close)...]
        }
        return names
    }

    private static func applyText(_ element: inout PageElement, text: String) {
        switch element.kind {
        case .text(_, let height):
            element.kind = .text(text, heightMm: height)
            element.name = String(text.prefix(40))
        case .textBox(_, let style):
            element.kind = .textBox(text: text, style: style)
            element.name = String(text.prefix(40))
        default:
            element.kind = .textBox(text: text, style: TextBoxStyle())
            element.name = String(text.prefix(40))
        }
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}
