import XCTest
@testable import CNCCore

final class PrecisionComposerCorrectionsTests: XCTestCase {
    private let longParagraph: String = {
        let sentence = "The quick brown fox jumps over the lazy dog while the plotter draws precise millimetre paths across the page. "
        var text = ""
        while text.count < 520 {
            text += sentence
        }
        return text
    }()

    func testGCodeDrawingGeometryMatchesPreview() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        let style = TextBoxStyle(fontSizeMm: 6, heightMode: .automatic, overflowPolicy: .expandBox)
        page.elements = [
            PageElement(
                name: "Letter",
                kind: .textBox(text: "HELLO PATH PARITY 123", style: style),
                xMm: 15,
                yMm: 20,
                widthMm: 160,
                heightMm: 20,
                layerID: page.defaultLayerID
            ),
        ]
        page.applyTextBoxSizing()
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: false)
        let previewPoints = PlotGeometry.drawingPoints(from: composed.job)
        let gcodePoints = PlotGeometry.drawingPoints(fromGCode: composed.gcode, profile: .ta4)
        XCTAssertFalse(previewPoints.isEmpty)
        XCTAssertEqual(previewPoints.count, gcodePoints.count)
        XCTAssertTrue(
            PlotGeometry.pointsMatch(previewPoints, gcodePoints, tolerance: 0.05),
            "G-code XY drawing geometry must match preview job"
        )
    }

    func testLongParagraphPlotsAllSupportedCharacters() throws {
        XCTAssertGreaterThanOrEqual(longParagraph.count, 500)
        let supported = PlotGeometry.supportedDrawableCharacterCount(in: longParagraph)
        XCTAssertGreaterThan(supported, 400)

        var page = PageDocument(format: .a5Landscape, bedOriginX: 15, bedOriginY: 15)
        let style = TextBoxStyle(fontSizeMm: 4.5, heightMode: .automatic, overflowPolicy: .expandBox)
        page.elements = [
            PageElement(
                name: "Long",
                kind: .textBox(text: longParagraph, style: style),
                xMm: 8,
                yMm: 8,
                widthMm: 190,
                heightMm: 30,
                layerID: page.defaultLayerID
            ),
        ]
        page.applyTextBoxSizing()
        XCTAssertGreaterThan(page.elements[0].heightMm, 30)
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: false)
        XCTAssertFalse(composed.hasBlockingOverflow)
        let drawPoints = PlotGeometry.drawingPoints(from: composed.job)
        // Each supported glyph contributes multiple stroke points; require substantial geometry.
        XCTAssertGreaterThan(drawPoints.count, supported)
        XCTAssertTrue(PlotGeometry.pointsMatch(
            drawPoints,
            PlotGeometry.drawingPoints(fromGCode: composed.gcode, profile: .ta4)
        ))
    }

    func testOverflowCannotBeClearedWithoutResolving() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        let style = TextBoxStyle(fontSizeMm: 8, heightMode: .fixed, overflowPolicy: .showOverflow)
        page.elements = [
            PageElement(
                name: "Tight",
                kind: .textBox(text: longParagraph, style: style),
                xMm: 10,
                yMm: 10,
                widthMm: 80,
                heightMm: 20,
                layerID: page.defaultLayerID
            ),
        ]
        XCTAssertTrue(page.hasTextOverflow())
        // Fixed height does not expand — overflow remains a hard blocker.
        page.applyTextBoxSizing()
        XCTAssertTrue(page.hasTextOverflow())
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: false)
        XCTAssertTrue(composed.hasBlockingOverflow)
    }

    func testAutomaticHeightPersistsThroughSaveOpen() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        let style = TextBoxStyle(fontSizeMm: 5, heightMode: .automatic, overflowPolicy: .showOverflow)
        page.elements = [
            PageElement(
                name: "Auto",
                kind: .textBox(text: longParagraph, style: style),
                xMm: 10,
                yMm: 10,
                widthMm: 170,
                heightMm: 20,
                layerID: page.defaultLayerID
            ),
        ]
        page.applyTextBoxSizing()
        let heightBefore = page.elements[0].heightMm
        XCTAssertGreaterThan(heightBefore, 20)

        let project = QuillProject(page: page)
        let data = try project.jsonData()
        let loaded = try QuillProject.load(from: data)
        XCTAssertEqual(loaded.page.elements[0].heightMm, heightBefore, accuracy: 0.05)
        if case .textBox(_, let s) = loaded.page.elements[0].kind {
            XCTAssertEqual(s.heightMode, .automatic)
        } else {
            XCTFail("expected textBox")
        }
        let composed = try PageComposer.compose(loaded.page, profile: .ta4, optimize: false)
        XCTAssertFalse(composed.hasBlockingOverflow)
    }

    func testOutlineAndTruncateCannotSilentlyFallback() throws {
        var outlineStyle = TextBoxStyle(fontSizeMm: 8)
        outlineStyle.fontKind = .outline
        XCTAssertFalse(outlineStyle.fontKind.isImplemented)
        let outlineLayout = TextLayoutEngine.layout(
            text: "Hello",
            boxWidthMm: 80,
            boxHeightMm: 30,
            style: outlineStyle
        )
        XCTAssertTrue(outlineLayout.overflows)
        XCTAssertTrue(outlineLayout.lines.isEmpty)
        XCTAssertThrowsError(try TextLayoutEngine.validateStyle(outlineStyle))

        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        page.elements = [
            PageElement(
                name: "Outline",
                kind: .textBox(text: "Hello", style: outlineStyle),
                layerID: page.defaultLayerID
            ),
        ]
        XCTAssertThrowsError(try PageComposer.compose(page, profile: .ta4))

        let truncateStyle = TextBoxStyle(fontSizeMm: 8, overflowPolicy: .truncateConfirmed)
        XCTAssertFalse(truncateStyle.overflowPolicy.isImplemented)
        let truncateLayout = TextLayoutEngine.layout(
            text: longParagraph,
            boxWidthMm: 40,
            boxHeightMm: 12,
            style: truncateStyle
        )
        XCTAssertTrue(truncateLayout.overflows)
        XCTAssertTrue(truncateLayout.lines.isEmpty)
        XCTAssertThrowsError(try TextLayoutEngine.validateStyle(truncateStyle))
    }

    func testUndoTransactionBoundaries() {
        var project = QuillProject()
        project.page.name = "Start"
        let history = DocumentHistory()

        // Geometry gesture: one transaction → one undo entry.
        XCTAssertTrue(history.beginTransaction(project))
        project.page.bedOriginX = 33
        project.page.bedOriginY = 44
        history.endTransaction()
        XCTAssertEqual(history.undoCount, 1)

        // Text edit coalesced.
        XCTAssertTrue(history.beginTransaction(project))
        project.page.name = "T"
        project.page.name = "Te"
        project.page.name = "Text"
        history.endTransaction()
        XCTAssertEqual(history.undoCount, 2)

        // Layer-like page mutation.
        XCTAssertTrue(history.beginTransaction(project))
        project.page.layers[0].pen.pressure = 0.9
        project.page.layers[0].pen.drawFeed = 1200
        project.page.layers[0].visible = false
        history.endTransaction()
        XCTAssertEqual(history.undoCount, 3)

        // Nested begin while open does not add another checkpoint.
        XCTAssertTrue(history.beginTransaction(project))
        XCTAssertFalse(history.beginTransaction(project))
        project.page.editor.gridSpacingMm = 2.5
        history.endTransaction()
        XCTAssertEqual(history.undoCount, 4)

        let afterLayer = history.undo(current: project)!
        XCTAssertEqual(afterLayer.page.layers[0].pen.pressure, 0.9, accuracy: 0.001)
        // Undo text transaction
        let afterText = history.undo(current: afterLayer)!
        XCTAssertEqual(afterText.page.name, "Text")
        let afterGeom = history.undo(current: afterText)!
        XCTAssertEqual(afterGeom.page.bedOriginX, 33, accuracy: 0.001)
        let start = history.undo(current: afterGeom)!
        XCTAssertEqual(start.page.name, "Start")
        XCTAssertEqual(start.page.bedOriginX, 20, accuracy: 0.001) // default
    }

    func testRejectedBatchRecordsNeverEnterPlotting() {
        let csv = """
        name,message
        Ada,Hi
        Grace,\(longParagraph)
        """
        let parsed = VariableData.parseCSV(csv)
        var page = PageDocument(format: .placeCard, bedOriginX: 50, bedOriginY: 50)
        let style = TextBoxStyle(fontSizeMm: 8, heightMode: .fixed, overflowPolicy: .showOverflow)
        let el = PageElement(
            name: "Msg",
            kind: .textBox(text: "{message}", style: style),
            xMm: 5,
            yMm: 5,
            widthMm: 60,
            heightMm: 18,
            layerID: page.defaultLayerID
        )
        page.elements = [el]
        var batch = VariableData.makeBatch(
            template: page,
            fieldMap: [el.id: "{message}"],
            rows: parsed.rows
        )
        batch.pages = VariableData.validateRecords(batch: batch)

        XCTAssertFalse(VariableData.isBlocked(batch.pages[0]))
        XCTAssertTrue(VariableData.isBlocked(batch.pages[1]))
        XCTAssertTrue(batch.pages[1].overflows)

        // Simulate queue gate: blocked records become failed, never plotting.
        for i in batch.pages.indices {
            if VariableData.isBlocked(batch.pages[i]) {
                batch.pages[i].status = .failed
            } else {
                batch.pages[i].status = .plotting
            }
        }
        XCTAssertEqual(batch.pages[0].status, .plotting)
        XCTAssertEqual(batch.pages[1].status, .failed)
        XCTAssertNotEqual(batch.pages[1].status, .plotting)
    }

    func testMultilineParagraphBreaksSurviveQuillRoundTrip() throws {
        let paragraph = """
        Dear guest,

        Welcome to the table.
        Please enjoy the evening.

        With gratitude,
        The hosts
        """
        XCTAssertTrue(paragraph.contains("\n"))
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        page.elements = [
            PageElement(
                name: "Letter",
                kind: .textBox(text: paragraph, style: TextBoxStyle(fontSizeMm: 6, heightMode: .automatic)),
                xMm: 10,
                yMm: 10,
                widthMm: 160,
                heightMm: 40,
                layerID: page.defaultLayerID
            ),
        ]
        page.applyTextBoxSizing()
        let data = try QuillProject(page: page).jsonData()
        let loaded = try QuillProject.load(from: data)
        let expectedLineCount = paragraph.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        XCTAssertEqual(expectedLineCount, 7, "sample letter should keep blank paragraph breaks")
        if case .textBox(let text, _) = loaded.page.elements[0].kind {
            XCTAssertEqual(text, paragraph)
            XCTAssertEqual(
                text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count,
                expectedLineCount
            )
            XCTAssertTrue(text.contains("\n\n"), "blank paragraph breaks must survive .quill round-trip")
        } else {
            XCTFail("expected textBox")
        }
        let layout = TextLayoutEngine.layout(
            text: paragraph,
            boxWidthMm: 160,
            boxHeightMm: loaded.page.elements[0].heightMm,
            style: TextBoxStyle(fontSizeMm: 6, heightMode: .automatic)
        )
        XCTAssertGreaterThan(layout.lines.count, 3)
        XCTAssertFalse(layout.overflows)
    }

    func testPortraitA4DoesNotFitTA4Bed() {
        // TA-4 bed is 390×200 mm — A4 portrait (210×297) and A4 landscape (297×210) both exceed height.
        XCTAssertFalse(PageFormat.a4Portrait.fits(on: .ta4))
        XCTAssertFalse(PageFormat.a4Landscape.fits(on: .ta4))
        XCTAssertTrue(PageFormat.a5Landscape.fits(on: .ta4))
        var page = PageDocument(format: .a4Portrait, bedOriginX: 0, bedOriginY: 0)
        page.elements = [
            PageElement(
                name: "T",
                kind: .textBox(text: "Hi", style: TextBoxStyle()),
                layerID: page.defaultLayerID
            ),
        ]
        XCTAssertThrowsError(try PageComposer.compose(page, profile: .ta4)) { error in
            guard let pageError = error as? PageComposerError,
                  case .pageDoesNotFitBed = pageError else {
                return XCTFail("expected pageDoesNotFitBed")
            }
        }
    }

    func testExpandBoxPersistsHeightOnDocument() {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        let style = TextBoxStyle(fontSizeMm: 6, heightMode: .fixed, overflowPolicy: .expandBox)
        page.elements = [
            PageElement(
                name: "Expand",
                kind: .textBox(text: longParagraph, style: style),
                xMm: 10,
                yMm: 10,
                widthMm: 160,
                heightMm: 18,
                layerID: page.defaultLayerID
            ),
        ]
        XCTAssertTrue(page.applyTextBoxSizing())
        let h = page.elements[0].heightMm
        XCTAssertGreaterThan(h, 18)
        // Second pass is stable.
        XCTAssertFalse(page.applyTextBoxSizing())
        XCTAssertEqual(page.elements[0].heightMm, h, accuracy: 0.05)
        XCTAssertFalse(page.hasTextOverflow())
    }
}
