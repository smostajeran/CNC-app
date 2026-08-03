import Foundation

public enum TextAlignment: String, Equatable, Sendable, Codable, CaseIterable {
    case left, center, right
}

public enum TextHeightMode: String, Equatable, Sendable, Codable, CaseIterable {
    case automatic
    case fixed
}

public enum TextOverflowPolicy: String, Equatable, Sendable, Codable, CaseIterable {
    /// Show overflow warning; never crop.
    case showOverflow
    case expandBox
    case reduceFontSize
    /// Not implemented — must never silently truncate.
    case truncateConfirmed

    public var isImplemented: Bool {
        switch self {
        case .showOverflow, .expandBox, .reduceFontSize: return true
        case .truncateConfirmed: return false
        }
    }
}

public enum FontKind: String, Equatable, Sendable, Codable, CaseIterable {
    case singleLinePlotter
    /// Not implemented — must never silently fall back to stick font.
    case outline

    public var isImplemented: Bool {
        switch self {
        case .singleLinePlotter: return true
        case .outline: return false
        }
    }
}

public enum TextLayoutError: Error, LocalizedError, Equatable {
    case unimplementedFont(FontKind)
    case unimplementedOverflowPolicy(TextOverflowPolicy)

    public var errorDescription: String? {
        switch self {
        case .unimplementedFont(let kind):
            return "Font kind “\(kind.rawValue)” is not implemented yet."
        case .unimplementedOverflowPolicy(let policy):
            return "Overflow policy “\(policy.rawValue)” is not implemented yet."
        }
    }
}

/// Typography for a multiline text box (all sizes in millimetres unless noted).
public struct TextBoxStyle: Equatable, Sendable, Codable {
    public var fontSizeMm: Double
    public var fontKind: FontKind
    public var fontName: String
    public var alignment: TextAlignment
    public var lineSpacingMm: Double
    public var paragraphSpacingMm: Double
    public var letterSpacingEm: Double
    public var wordSpacingEm: Double
    public var baselineOffsetMm: Double
    public var paddingMm: Double
    public var heightMode: TextHeightMode
    public var overflowPolicy: TextOverflowPolicy
    public var isRTL: Bool

    public init(
        fontSizeMm: Double = 8,
        fontKind: FontKind = .singleLinePlotter,
        fontName: String = "Quill Stick",
        alignment: TextAlignment = .left,
        lineSpacingMm: Double = 2,
        paragraphSpacingMm: Double = 4,
        letterSpacingEm: Double = 0.15,
        wordSpacingEm: Double = 0,
        baselineOffsetMm: Double = 0,
        paddingMm: Double = 2,
        heightMode: TextHeightMode = .automatic,
        overflowPolicy: TextOverflowPolicy = .showOverflow,
        isRTL: Bool = false
    ) {
        self.fontSizeMm = max(1, fontSizeMm)
        self.fontKind = fontKind
        self.fontName = fontName
        self.alignment = alignment
        self.lineSpacingMm = max(0, lineSpacingMm)
        self.paragraphSpacingMm = max(0, paragraphSpacingMm)
        self.letterSpacingEm = letterSpacingEm
        self.wordSpacingEm = wordSpacingEm
        self.baselineOffsetMm = baselineOffsetMm
        self.paddingMm = max(0, paddingMm)
        self.heightMode = heightMode
        self.overflowPolicy = overflowPolicy
        self.isRTL = isRTL
    }
}

public struct TextLineLayout: Equatable, Sendable {
    public var text: String
    public var widthMm: Double
    public var baselineYMm: Double
    public var xOffsetMm: Double

    public init(text: String, widthMm: Double, baselineYMm: Double, xOffsetMm: Double) {
        self.text = text
        self.widthMm = widthMm
        self.baselineYMm = baselineYMm
        self.xOffsetMm = xOffsetMm
    }
}

public struct TextLayoutResult: Equatable, Sendable {
    public var lines: [TextLineLayout]
    public var contentHeightMm: Double
    public var contentWidthMm: Double
    public var overflows: Bool
    public var overflowMessage: String?
    public var missingGlyphs: [Character]
    public var usedFontSizeMm: Double
    public var isRTL: Bool

    public init(
        lines: [TextLineLayout],
        contentHeightMm: Double,
        contentWidthMm: Double,
        overflows: Bool,
        overflowMessage: String?,
        missingGlyphs: [Character],
        usedFontSizeMm: Double,
        isRTL: Bool
    ) {
        self.lines = lines
        self.contentHeightMm = contentHeightMm
        self.contentWidthMm = contentWidthMm
        self.overflows = overflows
        self.overflowMessage = overflowMessage
        self.missingGlyphs = missingGlyphs
        self.usedFontSizeMm = usedFontSizeMm
        self.isRTL = isRTL
    }
}

/// Word-wrapping layout for single-line plotter fonts (mm space, Y up inside the text box).
public enum TextLayoutEngine {
    public static func detectRTL(_ text: String) -> Bool {
        for ch in text.unicodeScalars {
            // Arabic / Hebrew blocks
            if (0x0600...0x06FF).contains(ch.value)
                || (0x0750...0x077F).contains(ch.value)
                || (0x08A0...0x08FF).contains(ch.value)
                || (0xFB50...0xFDFF).contains(ch.value)
                || (0xFE70...0xFEFF).contains(ch.value)
                || (0x0590...0x05FF).contains(ch.value) {
                return true
            }
        }
        return false
    }

    public static func missingGlyphs(in text: String) -> [Character] {
        var missing: [Character] = []
        var seen = Set<Character>()
        for ch in text where !ch.isNewline && ch != " " && ch != "\t" {
            if !SingleLineText.hasGlyph(for: ch), seen.insert(ch).inserted {
                missing.append(ch)
            }
        }
        return missing
    }

    /// Validates that style options are implemented; throws instead of silent fallback.
    public static func validateStyle(_ style: TextBoxStyle) throws {
        if !style.fontKind.isImplemented {
            throw TextLayoutError.unimplementedFont(style.fontKind)
        }
        if !style.overflowPolicy.isImplemented {
            throw TextLayoutError.unimplementedOverflowPolicy(style.overflowPolicy)
        }
    }

    public static func layout(
        text: String,
        boxWidthMm: Double,
        boxHeightMm: Double,
        style: TextBoxStyle
    ) -> TextLayoutResult {
        // Refuse unimplemented options rather than silently falling back.
        if !style.fontKind.isImplemented || !style.overflowPolicy.isImplemented {
            return TextLayoutResult(
                lines: [],
                contentHeightMm: 0,
                contentWidthMm: 0,
                overflows: true,
                overflowMessage: !style.fontKind.isImplemented
                    ? "Outline fonts are not implemented yet."
                    : "Truncate is not implemented — choose Show overflow, Expand box, or Reduce font.",
                missingGlyphs: [],
                usedFontSizeMm: style.fontSizeMm,
                isRTL: style.isRTL || detectRTL(text)
            )
        }

        var workingStyle = style
        if workingStyle.isRTL == false {
            workingStyle.isRTL = detectRTL(text)
        }

        var fontSize = workingStyle.fontSizeMm
        var result = layoutOnce(
            text: text,
            boxWidthMm: boxWidthMm,
            boxHeightMm: boxHeightMm,
            style: workingStyle,
            fontSize: fontSize
        )

        if result.overflows, workingStyle.overflowPolicy == .reduceFontSize {
            var lo = 2.0
            var hi = fontSize
            for _ in 0..<12 {
                let mid = (lo + hi) / 2
                let attempt = layoutOnce(
                    text: text,
                    boxWidthMm: boxWidthMm,
                    boxHeightMm: boxHeightMm,
                    style: workingStyle,
                    fontSize: mid
                )
                if attempt.overflows {
                    hi = mid
                } else {
                    lo = mid
                    result = attempt
                    fontSize = mid
                }
            }
            result.usedFontSizeMm = fontSize
            if result.overflows {
                result.overflowMessage = "Text still overflows after reducing font size to \(String(format: "%.1f", fontSize)) mm."
            }
        }

        return result
    }

    /// Build plot paths for laid-out lines. Origin is bottom-left of the text box (padding applied).
    public static func plotJob(
        layout: TextLayoutResult,
        style: TextBoxStyle
    ) -> PlotJob {
        var commands: [PlotCommand] = []
        let fontSize = layout.usedFontSizeMm
        for line in layout.lines {
            let display: String
            if layout.isRTL {
                display = String(line.text.reversed())
            } else {
                display = line.text
            }
            let job = SingleLineText.plotJob(
                text: display,
                heightMm: fontSize,
                origin: PlotPoint(
                    x: style.paddingMm + line.xOffsetMm,
                    y: style.paddingMm + line.baselineYMm + style.baselineOffsetMm
                ),
                letterSpacing: style.letterSpacingEm
            )
            commands.append(contentsOf: job.commands)
        }
        return PlotJob(commands: commands)
    }

    private static func layoutOnce(
        text: String,
        boxWidthMm: Double,
        boxHeightMm: Double,
        style: TextBoxStyle,
        fontSize: Double
    ) -> TextLayoutResult {
        let missing = missingGlyphs(in: text)
        let innerWidth = max(boxWidthMm - style.paddingMm * 2, 1)
        let innerHeight = max(boxHeightMm - style.paddingMm * 2, 1)

        let paragraphs = text.components(separatedBy: "\n")
        var lines: [(String, Double)] = []

        for (pIndex, paragraph) in paragraphs.enumerated() {
            let wrapped = wrapParagraph(
                paragraph,
                maxWidthMm: innerWidth,
                fontSize: fontSize,
                letterSpacingEm: style.letterSpacingEm,
                wordSpacingEm: style.wordSpacingEm
            )
            lines.append(contentsOf: wrapped)
            if pIndex < paragraphs.count - 1, style.paragraphSpacingMm > 0 {
                // Paragraph break represented as empty spacer line marker
                lines.append(("", -style.paragraphSpacingMm))
            }
        }

        var laid: [TextLineLayout] = []
        var yFromTop = 0.0
        var maxLineW = 0.0
        let lineHeight = fontSize + style.lineSpacingMm

        for (textLine, widthOrSpacer) in lines {
            if widthOrSpacer < 0 {
                yFromTop += -widthOrSpacer
                continue
            }
            let width = widthOrSpacer
            maxLineW = max(maxLineW, width)
            let xOffset: Double
            switch style.alignment {
            case .left: xOffset = 0
            case .center: xOffset = max((innerWidth - width) / 2, 0)
            case .right: xOffset = max(innerWidth - width, 0)
            }
            laid.append(TextLineLayout(
                text: textLine,
                widthMm: width,
                baselineYMm: 0, // filled after total height known
                xOffsetMm: xOffset
            ))
            yFromTop += lineHeight
            _ = textLine
        }

        let contentHeight = max(yFromTop - style.lineSpacingMm, fontSize)
        // Assign baselines from bottom of content box
        var cursorTop = 0.0
        var finalLines: [TextLineLayout] = []
        var lineIndex = 0
        for (textLine, widthOrSpacer) in lines {
            if widthOrSpacer < 0 {
                cursorTop += -widthOrSpacer
                continue
            }
            var line = laid[lineIndex]
            let baselineFromTop = cursorTop + fontSize
            line.baselineYMm = contentHeight - baselineFromTop
            finalLines.append(line)
            cursorTop += lineHeight
            lineIndex += 1
        }

        var overflows = false
        var message: String?
        if style.heightMode == .fixed && contentHeight > innerHeight + 0.05 {
            overflows = true
            message = String(
                format: "Text height %.1f mm exceeds box %.1f mm — content is not cropped.",
                contentHeight, innerHeight
            )
        }
        if maxLineW > innerWidth + 0.05 {
            overflows = true
            let widthMsg = String(format: "Line width %.1f mm exceeds box %.1f mm.", maxLineW, innerWidth)
            message = message.map { $0 + " " + widthMsg } ?? widthMsg
        }
        if !missing.isEmpty {
            let glyphs = missing.map(String.init).joined(separator: " ")
            let miss = "Missing plotter glyphs: \(glyphs)"
            message = message.map { $0 + " " + miss } ?? miss
        }

        return TextLayoutResult(
            lines: finalLines,
            contentHeightMm: contentHeight,
            contentWidthMm: maxLineW,
            overflows: overflows,
            overflowMessage: message,
            missingGlyphs: missing,
            usedFontSizeMm: fontSize,
            isRTL: style.isRTL || detectRTL(text)
        )
    }

    private static func wrapParagraph(
        _ paragraph: String,
        maxWidthMm: Double,
        fontSize: Double,
        letterSpacingEm: Double,
        wordSpacingEm: Double
    ) -> [(String, Double)] {
        if paragraph.isEmpty {
            return [("", 0)]
        }
        let words = paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var lines: [(String, Double)] = []
        var current = ""
        var currentWidth = 0.0

        func width(of s: String) -> Double {
            SingleLineText.measureWidthMm(
                s,
                heightMm: fontSize,
                letterSpacing: letterSpacingEm,
                wordSpacingExtraEm: wordSpacingEm
            )
        }

        for (idx, word) in words.enumerated() {
            let candidate = current.isEmpty ? word : current + " " + word
            let w = width(of: candidate)
            if w <= maxWidthMm || current.isEmpty {
                current = candidate
                currentWidth = w
            } else {
                lines.append((current, currentWidth))
                current = word
                currentWidth = width(of: word)
                // Hard-break oversized words
                while currentWidth > maxWidthMm, current.count > 1 {
                    var cut = current.count
                    while cut > 1 {
                        let head = String(current.prefix(cut))
                        if width(of: head) <= maxWidthMm { break }
                        cut -= 1
                    }
                    let head = String(current.prefix(cut))
                    lines.append((head, width(of: head)))
                    current = String(current.dropFirst(cut))
                    currentWidth = width(of: current)
                }
            }
            _ = idx
        }
        if !current.isEmpty || lines.isEmpty {
            lines.append((current, currentWidth))
        }
        return lines
    }
}
