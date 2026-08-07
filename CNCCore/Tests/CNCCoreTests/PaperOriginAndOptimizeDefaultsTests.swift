import XCTest
@testable import CNCCore

final class PaperOriginAndOptimizeDefaultsTests: XCTestCase {
    func testDefaultOptimizeIsLeftToRightNotSerpentine() {
        // Two rows with scrambled X order — LTR default must visit left→right on both rows.
        let job = PlotJob(commands: [
            .move(PlotPoint(x: 20, y: 20)), .line(PlotPoint(x: 28, y: 20)),
            .move(PlotPoint(x: 0, y: 20)), .line(PlotPoint(x: 8, y: 20)),
            .move(PlotPoint(x: 20, y: 5)), .line(PlotPoint(x: 28, y: 5)),
            .move(PlotPoint(x: 0, y: 5)), .line(PlotPoint(x: 8, y: 5)),
        ])
        let optimized = PathOptimizer.optimize(job)
        let paths = PathOptimizer.extractDrawPaths(from: optimized)
        XCTAssertEqual(paths.count, 4)
        // First stroke of each row should be the leftmost (x≈0), not rightmost.
        XCTAssertEqual(paths[0].points.map(\.x).min() ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(paths[2].points.map(\.x).min() ?? -1, 0, accuracy: 0.01)
    }

    func testComposeOptimizeUsesLTRVisitOrder() throws {
        var page = PageDocument(format: .placeCard, bedOriginX: 10, bedOriginY: 10)
        let layerID = page.defaultLayerID
        page.elements = [
            PageElement(
                name: "Line1",
                kind: .textBox(text: "AB CD", style: TextBoxStyle(fontSizeMm: 8, lineSpacingMm: 4, paddingMm: 1)),
                xMm: 5,
                yMm: 20,
                widthMm: 80,
                heightMm: 30,
                layerID: layerID
            ),
        ]
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: true)
        let plain = try PageComposer.compose(page, profile: .ta4, optimize: false)
        // Geometry (point sets) must match — no X-mirror from optimize.
        func fingerprints(_ job: PlotJob) -> Set<String> {
            Set(PathOptimizer.extractDrawPaths(from: job).map { path in
                path.points.map { String(format: "%.3f,%.3f", $0.x, $0.y) }.sorted().joined(separator: "|")
            })
        }
        XCTAssertEqual(fingerprints(composed.job), fingerprints(plain.job))
    }

    func testBedOriginClampsPaperInsideTravel() {
        var page = PageDocument(format: .a4OnTA4Bed, bedOriginX: 500, bedOriginY: 500)
        _ = page.migrateFormatToFitBed(.ta4)
        XCTAssertLessThanOrEqual(page.bedOriginX + page.format.widthMm, MachineProfile.ta4.travelX + 0.05)
        XCTAssertLessThanOrEqual(page.bedOriginY + page.format.heightMm, MachineProfile.ta4.travelY + 0.05)
        XCTAssertGreaterThanOrEqual(page.bedOriginX, 0)
        XCTAssertGreaterThanOrEqual(page.bedOriginY, 0)
    }
}
