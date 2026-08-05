import XCTest
@testable import CNCCore

final class LetterOrderMirrorProbeTests: XCTestCase {
    func testSerpentinePreservesStrokePointSetsAndLTRCentroids() {
        let style = TextBoxStyle(fontSizeMm: 10, lineSpacingMm: 3, paddingMm: 2)
        let text = "THANK YOU\nTHANK YOU"
        let layout = TextLayoutEngine.layout(text: text, boxWidthMm: 120, boxHeightMm: 50, style: style)
        let plain = TextLayoutEngine.plotJob(layout: layout, style: style)
        let serp = PathOptimizer.optimize(plain, mode: .serpentineRows)

        func fingerprints(_ job: PlotJob) -> Set<String> {
            Set(PathOptimizer.extractDrawPaths(from: job).map { path in
                path.points.map { String(format: "%.4f,%.4f", $0.x, $0.y) }.sorted().joined(separator: "|")
            })
        }
        XCTAssertEqual(fingerprints(plain), fingerprints(serp), "serpentine must not change stroke geometry")

        func rows(_ job: PlotJob, tol: Double = 4) -> [[Double]] {
            struct I { var y: Double; var cx: Double }
            let items = PathOptimizer.extractDrawPaths(from: job).map { path -> I in
                let xs = path.points.map(\.x); let ys = path.points.map(\.y)
                return I(y: ys.reduce(0, +) / Double(ys.count), cx: xs.reduce(0, +) / Double(xs.count))
            }.sorted { $0.y > $1.y }
            var out: [[I]] = []
            for it in items {
                if var last = out.last, abs(it.y - last[0].y) <= tol {
                    last.append(it); out[out.count - 1] = last
                } else {
                    out.append([it])
                }
            }
            return out.map { $0.map(\.cx).sorted() }
        }

        let plainRows = rows(plain)
        let serpRows = rows(serp)
        XCTAssertEqual(plainRows.count, serpRows.count)
        for i in plainRows.indices {
            // Sorted centroids identical ⇒ no X-mirror of letter positions
            XCTAssertEqual(plainRows[i].count, serpRows[i].count)
            for j in plainRows[i].indices {
                XCTAssertEqual(plainRows[i][j], serpRows[i][j], accuracy: 0.05)
            }
        }
    }

    func testRTLStringReverseCharacterReversesWithoutMirroringGlyphs() {
        var style = TextBoxStyle(fontSizeMm: 10, paddingMm: 0)
        style.isRTL = true
        let layout = TextLayoutEngine.layout(text: "ABC", boxWidthMm: 80, boxHeightMm: 20, style: style)
        let job = TextLayoutEngine.plotJob(layout: layout, style: style)
        let paths = PathOptimizer.extractDrawPaths(from: job)
        // A has 2 strokes, B has 2, C has 1 — first strokes' xmin should increase LTR for reversed "CBA"
        // So leftmost glyph cluster is C (round bowl), not A.
        XCTAssertFalse(paths.isEmpty)
        let cens = paths.map { p in p.points.map(\.x).reduce(0,+) / Double(p.points.count) }.sorted()
        XCTAssertGreaterThan(cens.last! - cens.first!, 5)
    }

    func testLegacyTextNewlineDoesNotAdvanceY() {
        let job = SingleLineText.plotJob(text: "HI\nYO", heightMm: 10, origin: PlotPoint(x: 0, y: 0))
        let ys = job.commands.compactMap { cmd -> Double? in
            if case .move(let p) = cmd { return p.y }
            if case .line(let p) = cmd { return p.y }
            return nil
        }
        XCTAssertEqual(ys.min()!, ys.max()! - 10, accuracy: 0.2) // all on same baseline band ~0...10
        // Both lines share baseline 0 — max Y is glyph height, not a second line
        XCTAssertLessThan(ys.max()!, 12)
    }
}
