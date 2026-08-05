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

    /// Serpentine: even rows LTR, odd rows RTL with each stroke reversed (not mirrored in X).
    func testSerpentineRowsAlternateDirectionWithoutMirroring() {
        // Top row (Y=20): three short strokes left→right in source order scrambled.
        // Bottom row (Y=5): three short strokes; must be visited right→left after optimize.
        let job = PlotJob(commands: [
            .move(PlotPoint(x: 20, y: 20)), .line(PlotPoint(x: 28, y: 20)), // C top
            .move(PlotPoint(x: 0, y: 20)), .line(PlotPoint(x: 8, y: 20)),   // A top
            .move(PlotPoint(x: 10, y: 20)), .line(PlotPoint(x: 18, y: 20)), // B top
            .move(PlotPoint(x: 0, y: 5)), .line(PlotPoint(x: 8, y: 5)),     // D bottom
            .move(PlotPoint(x: 20, y: 5)), .line(PlotPoint(x: 28, y: 5)),   // F bottom
            .move(PlotPoint(x: 10, y: 5)), .line(PlotPoint(x: 18, y: 5)),   // E bottom
        ])

        XCTAssertEqual(PathOptimizer.rowCount(for: job), 2)

        let optimized = PathOptimizer.optimize(job, mode: .serpentineRows)
        let paths = PathOptimizer.extractDrawPaths(from: optimized)
        XCTAssertEqual(paths.count, 6)

        // Top row LTR: A, B, C — original orientation (start.x < end.x).
        XCTAssertEqual(paths[0].start?.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(paths[1].start?.x ?? -1, 10, accuracy: 0.01)
        XCTAssertEqual(paths[2].start?.x ?? -1, 20, accuracy: 0.01)
        XCTAssertLessThan(paths[0].start!.x, paths[0].end!.x)

        // Bottom row RTL: F, E, D — each stroke reversed so start is former right end.
        XCTAssertEqual(paths[3].start?.x ?? -1, 28, accuracy: 0.01)
        XCTAssertEqual(paths[4].start?.x ?? -1, 18, accuracy: 0.01)
        XCTAssertEqual(paths[5].start?.x ?? -1, 8, accuracy: 0.01)
        XCTAssertGreaterThan(paths[3].start!.x, paths[3].end!.x)

        // Geometry extents preserved (polyline reverse ≠ X-mirror).
        let bottomExtents = paths[3...5].map { path -> (Double, Double) in
            let xs = path.points.map(\.x)
            return (xs.min()!, xs.max()!)
        }
        XCTAssertEqual(bottomExtents[0].0, 20, accuracy: 0.01)
        XCTAssertEqual(bottomExtents[0].1, 28, accuracy: 0.01)
        XCTAssertEqual(bottomExtents[1].0, 10, accuracy: 0.01)
        XCTAssertEqual(bottomExtents[2].0, 0, accuracy: 0.01)
    }

    /// Tall stick glyphs must not be shredded into LTR/RTL bands (the real mirror symptom).
    func testSerpentineKeepsSingleTextLineAsOneRow() {
        let style = TextBoxStyle(fontSizeMm: 12, lineSpacingMm: 3, paddingMm: 0)
        let layout = TextLayoutEngine.layout(
            text: "THANK YOU",
            boxWidthMm: 140,
            boxHeightMm: 30,
            style: style
        )
        XCTAssertEqual(layout.lines.count, 1)
        let job = TextLayoutEngine.plotJob(layout: layout, style: style)
        XCTAssertEqual(
            PathOptimizer.rowCount(for: job),
            1,
            "A single text line must be one serpentine row; 4 mm banding split glyph strokes"
        )

        let optimized = PathOptimizer.optimize(job, mode: .serpentineRows)
        let paths = PathOptimizer.extractDrawPaths(from: optimized)
        guard let first = paths.first, let last = paths.last else {
            XCTFail("expected strokes")
            return
        }
        // One LTR row: first stroke is leftmost, last is rightmost.
        let firstMinX = first.points.map(\.x).min()!
        let lastMaxX = last.points.map(\.x).max()!
        let allMin = paths.flatMap(\.points).map(\.x).min()!
        let allMax = paths.flatMap(\.points).map(\.x).max()!
        XCTAssertEqual(firstMinX, allMin, accuracy: 0.05)
        XCTAssertEqual(lastMaxX, allMax, accuracy: 0.05)
    }

    func testSerpentineTwoTextLinesAreTwoRowsWithRTLSecond() {
        let style = TextBoxStyle(fontSizeMm: 12, lineSpacingMm: 4, paddingMm: 0)
        let layout = TextLayoutEngine.layout(
            text: "THANK YOU\nTHANK YOU",
            boxWidthMm: 140,
            boxHeightMm: 50,
            style: style
        )
        XCTAssertEqual(layout.lines.count, 2)
        let job = TextLayoutEngine.plotJob(layout: layout, style: style)
        XCTAssertEqual(PathOptimizer.rowCount(for: job), 2)

        let optimized = PathOptimizer.optimize(job, mode: .serpentineRows)
        let paths = PathOptimizer.extractDrawPaths(from: optimized)
        let midY = (paths.map { $0.points.map(\.y).reduce(0, +) / Double($0.points.count) }
            .min()! + paths.map { $0.points.map(\.y).reduce(0, +) / Double($0.points.count) }
            .max()!) / 2
        let top = paths.filter {
            $0.points.map(\.y).reduce(0, +) / Double($0.points.count) >= midY
        }
        let bottom = paths.filter {
            $0.points.map(\.y).reduce(0, +) / Double($0.points.count) < midY
        }
        // Top line plotted first (LTR): its paths appear before bottom in optimized order.
        let firstTopIdx = paths.firstIndex { path in
            path.points.map(\.y).reduce(0, +) / Double(path.points.count) >= midY
        }
        let firstBotIdx = paths.firstIndex { path in
            path.points.map(\.y).reduce(0, +) / Double(path.points.count) < midY
        }
        XCTAssertNotNil(firstTopIdx)
        XCTAssertNotNil(firstBotIdx)
        XCTAssertLessThan(firstTopIdx!, firstBotIdx!)

        // Bottom (odd) row is RTL: first bottom stroke is on the right side of that line.
        let bottomInOrder = paths.filter {
            $0.points.map(\.y).reduce(0, +) / Double($0.points.count) < midY
        }
        XCTAssertFalse(bottomInOrder.isEmpty)
        let bottomRight = bottom.map { $0.points.map(\.x).max()! }.max()!
        XCTAssertEqual(bottomInOrder.first!.points.map(\.x).max()!, bottomRight, accuracy: 0.05)

        // Centroids on each line still increase left→right when sorted (no X-mirror).
        for band in [top, bottom] {
            let cens = band.map { $0.points.map(\.x).reduce(0, +) / Double($0.points.count) }.sorted()
            XCTAssertEqual(cens.count, band.count)
            for i in 1..<cens.count {
                XCTAssertGreaterThanOrEqual(cens[i], cens[i - 1] - 0.01)
            }
        }
    }

    func testSerpentineKeepsMultiLineTextExtentsReadable() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 30, bedOriginY: 20)
        let style = TextBoxStyle(fontSizeMm: 10, lineSpacingMm: 4, paddingMm: 2)
        page.elements = [
            PageElement(
                name: "Thanks",
                kind: .textBox(text: "THANK YOU\nTHANK YOU", style: style),
                xMm: 15,
                yMm: 30,
                widthMm: 120,
                heightMm: 50,
                layerID: page.defaultLayerID
            ),
        ]
        let plain = try PageComposer.compose(page, profile: .ta4, optimize: false)
        let serpentine = try PageComposer.compose(page, profile: .ta4, optimize: true)

        // Same ink footprint — optimizer must not mirror alternate lines in X.
        XCTAssertEqual(plain.job.bounds.minX, serpentine.job.bounds.minX, accuracy: 0.05)
        XCTAssertEqual(plain.job.bounds.maxX, serpentine.job.bounds.maxX, accuracy: 0.05)
        XCTAssertEqual(plain.job.bounds.minY, serpentine.job.bounds.minY, accuracy: 0.05)
        XCTAssertEqual(plain.job.bounds.maxY, serpentine.job.bounds.maxY, accuracy: 0.05)
        XCTAssertEqual(
            PathOptimizer.extractDrawPaths(from: plain.job).count,
            PathOptimizer.extractDrawPaths(from: serpentine.job).count
        )
        XCTAssertEqual(PathOptimizer.rowCount(for: plain.job), 2)
    }

    func testLegacyTextNewlineAdvancesBaseline() {
        let job = SingleLineText.plotJob(text: "HI\nYO", heightMm: 10, origin: PlotPoint(x: 0, y: 40))
        let ys = job.commands.compactMap { cmd -> Double? in
            switch cmd {
            case .move(let p), .line(let p): return p.y
            case .penChange: return nil
            }
        }
        XCTAssertGreaterThan((ys.max() ?? 0) - (ys.min() ?? 0), 15, "second line must drop in Y")
    }

    func testOptimizePreservesPenChangeMarkers() throws {
        var page = PageDocument(format: .placeCard, bedOriginX: 40, bedOriginY: 40)
        let pen1 = page.defaultLayerID
        let pen2 = page.addLayer(named: "Red", pen: .marker)
        page.elements = [
            PageElement(name: "A", kind: .text("A", heightMm: 8), xMm: 5, yMm: 10, layerID: pen1),
            PageElement(name: "B", kind: .text("B", heightMm: 8), xMm: 30, yMm: 10, layerID: pen2),
        ]
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: true)
        XCTAssertTrue(composed.gcode.contains("M0"))
        XCTAssertEqual(composed.optimizedMetrics.penChanges, 1)
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
