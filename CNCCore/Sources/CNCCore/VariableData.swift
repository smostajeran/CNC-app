import Foundation

/// One generated page in a variable-data batch.
public struct BatchPage: Equatable, Sendable, Identifiable {
    public enum Status: String, Equatable, Sendable {
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

    public init(
        id: UUID = UUID(),
        index: Int,
        values: [String: String],
        status: Status = .pending,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.index = index
        self.values = values
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct BatchDocument: Equatable, Sendable {
    public var template: PageDocument
    /// Element id → template string with `{field}` placeholders.
    public var fieldMap: [UUID: String]
    public var pages: [BatchPage]
    public var pauseBetweenPages: Bool
    public var currentIndex: Int

    public init(
        template: PageDocument = PageDocument(),
        fieldMap: [UUID: String] = [:],
        pages: [BatchPage] = [],
        pauseBetweenPages: Bool = true,
        currentIndex: Int = 0
    ) {
        self.template = template
        self.fieldMap = fieldMap
        self.pages = pages
        self.pauseBetweenPages = pauseBetweenPages
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
        return BatchDocument(
            template: template,
            fieldMap: fieldMap,
            pages: pages,
            pauseBetweenPages: pauseBetweenPages
        )
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
                switch el.kind {
                case .text(_, let height):
                    copy.kind = .text(text, heightMm: height)
                    copy.name = text
                default:
                    break
                }
            } else if case .text(let raw, let height) = el.kind, raw.contains("{") {
                copy.kind = .text(apply(raw, values: page.values), heightMm: height)
            }
            return copy
        }
        return doc
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
