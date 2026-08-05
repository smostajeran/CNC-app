import XCTest
@testable import CNCCore

final class PageComposerTests: XCTestCase {
    func testComposeTextOnA5() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 30, bedOriginY: 20)
        let layerID = page.defaultLayerID
        page.elements = [
            PageElement(
                name: "Greeting",
                kind: .text("Hello", heightMm: 12),
                xMm: 20,
                yMm: 40,
                layerID: layerID
            ),
        ]
        let composed = try PageComposer.compose(page, profile: .ta4)
        XCTAssertFalse(composed.gcode.isEmpty)
        XCTAssertTrue(composed.gcode.contains("G1"))
        XCTAssertGreaterThan(composed.metrics.drawDistanceMm, 0)
        XCTAssertTrue(composed.frameGCode.contains("G0 Z"))
        // Finished jobs must park at work origin (homed corner) with pen up.
        XCTAssertTrue(
            composed.gcode.contains("G0 X0 Y0") || composed.gcode.contains("G0 X0.000 Y0.000"),
            "Compose G-code should return to X0 Y0 after the last stroke"
        )
        XCTAssertTrue(composed.gcode.contains("M2"))
    }

    func testPageOutsideBedFails() {
        var page = PageDocument(format: .a4Portrait, bedOriginX: 0, bedOriginY: 0)
        page.elements = [
            PageElement(name: "T", kind: .text("A", heightMm: 10), layerID: page.defaultLayerID),
        ]
        XCTAssertThrowsError(try PageComposer.compose(page, profile: .ta4))
    }

    func testMultiPenInsertsM0() throws {
        var page = PageDocument(format: .placeCard, bedOriginX: 40, bedOriginY: 40)
        let pen1 = page.defaultLayerID
        let pen2 = page.addLayer(named: "Red", pen: .marker)
        page.elements = [
            PageElement(name: "A", kind: .text("A", heightMm: 8), xMm: 5, yMm: 10, layerID: pen1),
            PageElement(name: "B", kind: .text("B", heightMm: 8), xMm: 30, yMm: 10, layerID: pen2),
        ]
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: false)
        XCTAssertTrue(composed.gcode.contains("M0"))
        XCTAssertEqual(composed.metrics.penChanges, 1)
    }

    func testOptimizerReducesTravel() {
        let job = PlotJob(commands: [
            .move(PlotPoint(x: 0, y: 0)),
            .line(PlotPoint(x: 10, y: 0)),
            .move(PlotPoint(x: 100, y: 0)),
            .line(PlotPoint(x: 110, y: 0)),
            .move(PlotPoint(x: 12, y: 0)),
            .line(PlotPoint(x: 20, y: 0)),
        ])
        let before = PathOptimizer.metrics(for: job, drawFeed: 1500, travelFeed: 3000)
        let afterJob = PathOptimizer.optimize(job)
        let after = PathOptimizer.metrics(for: afterJob, drawFeed: 1500, travelFeed: 3000)
        XCTAssertLessThanOrEqual(after.travelDistanceMm, before.travelDistanceMm + 0.01)
    }

    func testCSVVariableData() throws {
        let csv = """
        name,table
        Ada,1
        Grace,2
        """
        let parsed = VariableData.parseCSV(csv)
        XCTAssertEqual(parsed.headers, ["name", "table"])
        XCTAssertEqual(parsed.rows.count, 2)

        var page = PageDocument(format: .placeCard, bedOriginX: 50, bedOriginY: 50)
        let el = PageElement(
            name: "Name",
            kind: .text("{name}", heightMm: 10),
            xMm: 10,
            yMm: 15,
            layerID: page.defaultLayerID
        )
        page.elements = [el]
        let batch = VariableData.makeBatch(
            template: page,
            fieldMap: [el.id: "{name}"],
            rows: parsed.rows
        )
        let material = VariableData.materialize(batch: batch, pageID: batch.pages[0].id)!
        if case .text(let t, _) = material.elements[0].kind {
            XCTAssertEqual(t, "Ada")
        } else {
            XCTFail("expected text")
        }
        let composed = try PageComposer.compose(material, profile: .ta4)
        XCTAssertTrue(composed.gcode.contains("G1"))
    }
}
