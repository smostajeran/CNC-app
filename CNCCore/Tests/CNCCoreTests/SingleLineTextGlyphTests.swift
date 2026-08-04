import XCTest
@testable import CNCCore

final class SingleLineTextGlyphTests: XCTestCase {
    func testUppercaseDigitsAndLegacyPunctuationStillPresent() {
        let legacy = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,-'?!:/"
        for ch in legacy {
            XCTAssertTrue(SingleLineText.hasGlyph(for: ch), "missing legacy glyph \(ch)")
        }
    }

    func testProperLowercaseAlphabetIsDefined() {
        let lower = "abcdefghijklmnopqrstuvwxyz"
        for ch in lower {
            XCTAssertTrue(
                SingleLineText.definedGlyphCharacters.contains(ch),
                "lowercase \(ch) must be an explicit glyph, not only uppercase fallback"
            )
            XCTAssertTrue(SingleLineText.hasGlyph(for: ch))
        }
        XCTAssertEqual(lower.filter { SingleLineText.definedGlyphCharacters.contains($0) }.count, 26)
    }

    func testDescendersExtendBelowBaseline() {
        for ch in ["g", "j", "p", "q", "y"] as [Character] {
            let job = SingleLineText.plotJob(text: String(ch), heightMm: 10, origin: PlotPoint(x: 0, y: 0))
            let ys = job.commands.compactMap { cmd -> Double? in
                switch cmd {
                case .move(let p), .line(let p): return p.y
                case .penChange: return nil
                }
            }
            XCTAssertFalse(ys.isEmpty, "\(ch) should draw strokes")
            XCTAssertLessThan(ys.min() ?? 0, -1.0, "\(ch) should have a descender below baseline")
        }
    }

    func testAscendersReachNearCapHeight() {
        for ch in ["b", "d", "f", "h", "k", "l", "t"] as [Character] {
            let job = SingleLineText.plotJob(text: String(ch), heightMm: 10, origin: PlotPoint(x: 0, y: 0))
            let ys = job.commands.compactMap { cmd -> Double? in
                switch cmd {
                case .move(let p), .line(let p): return p.y
                case .penChange: return nil
                }
            }
            XCTAssertGreaterThan(ys.max() ?? 0, 8.5, "\(ch) should reach near cap height at 10 mm")
        }
    }

    func testLowercaseIsNotIdenticalToScaledUppercaseFallbackShape() {
        // 'a' should be a distinct single-story form; plotting "a" vs "A" at same height
        // must not produce identical command counts/geometry.
        let lower = SingleLineText.plotJob(text: "a", heightMm: 10, origin: PlotPoint(x: 0, y: 0))
        let upper = SingleLineText.plotJob(text: "A", heightMm: 10, origin: PlotPoint(x: 0, y: 0))
        XCTAssertNotEqual(lower.commands.count, upper.commands.count)
    }

    func testAddressAndLetterPunctuationSupported() {
        let sample = #"Dear guest, write to hello@example.com / #12B & co. (RSVP?) — wait: 50% + $20 = ok; "yes"!"#
        // Em-dash is not required; normalize to ASCII hyphen for stick font.
        let ascii = sample.replacingOccurrences(of: "—", with: "-")
        XCTAssertTrue(SingleLineText.canDrawAllCharacters(in: ascii), ascii)
        let job = SingleLineText.plotJob(text: ascii, heightMm: 6, origin: PlotPoint(x: 0, y: 0))
        XCTAssertGreaterThan(job.commands.count, 50)
    }

    func testMultilineLetterParagraphFullyDrawable() {
        let paragraph = """
        Dear guest,

        Welcome to the table.
        Please enjoy the evening.

        With gratitude,
        The hosts
        """
        XCTAssertTrue(SingleLineText.canDrawAllCharacters(in: paragraph))
        let job = SingleLineText.plotJob(text: paragraph.replacingOccurrences(of: "\n", with: " "), heightMm: 5)
        XCTAssertFalse(job.commands.isEmpty)
    }

    func testMeasureWidthPositiveForWords() {
        let width = SingleLineText.measureWidthMm("Thank you", heightMm: 8)
        XCTAssertGreaterThan(width, 20)
        XCTAssertLessThan(width, 80)
    }

    func testMissingGlyphsStillReported() {
        XCTAssertFalse(SingleLineText.hasGlyph(for: "©"))
        XCTAssertFalse(SingleLineText.hasGlyph(for: "é"))
        XCTAssertFalse(SingleLineText.canDrawAllCharacters(in: "café"))
    }
}
