import XCTest
@testable import CNCCore

final class PrecisionComposerTests: XCTestCase {
    private let longParagraph: String = {
        let sentence = "The quick brown fox jumps over the lazy dog while the plotter draws precise millimetre paths across the page. "
        var text = ""
        while text.count < 520 {
            text += sentence
        }
        return text
    }()

    func testParagraphWrapping500Chars() {
        let style = TextBoxStyle(fontSizeMm: 6, lineSpacingMm: 1.5, paddingMm: 2, heightMode: .automatic)
        let layout = TextLayoutEngine.layout(
            text: longParagraph,
            boxWidthMm: 120,
            boxHeightMm: 40,
            style: style
        )
        XCTAssertGreaterThanOrEqual(longParagraph.count, 500)
        XCTAssertGreaterThan(layout.lines.count, 1)
        XCTAssertGreaterThan(layout.contentHeightMm, style.fontSizeMm)
        for line in layout.lines {
            XCTAssertLessThanOrEqual(line.widthMm, 120 - style.paddingMm * 2 + 0.2)
        }
    }

    func testFixedHeightOverflowDetection() {
        let style = TextBoxStyle(fontSizeMm: 10, heightMode: .fixed, overflowPolicy: .showOverflow)
        let layout = TextLayoutEngine.layout(
            text: longParagraph,
            boxWidthMm: 80,
            boxHeightMm: 20,
            style: style
        )
        XCTAssertTrue(layout.overflows)
        XCTAssertNotNil(layout.overflowMessage)
    }

    func testAutomaticHeightDoesNotOverflow() {
        let style = TextBoxStyle(fontSizeMm: 8, heightMode: .automatic)
        let layout = TextLayoutEngine.layout(
            text: longParagraph,
            boxWidthMm: 100,
            boxHeightMm: 10,
            style: style
        )
        XCTAssertFalse(layout.overflows)
        XCTAssertGreaterThan(layout.contentHeightMm, 10)
    }

    func testLongParagraphProducesCompletePlotPaths() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        let style = TextBoxStyle(fontSizeMm: 5, heightMode: .automatic, overflowPolicy: .expandBox)
        page.elements = [
            PageElement(
                name: "Letter",
                kind: .textBox(text: longParagraph, style: style),
                xMm: 10,
                yMm: 10,
                widthMm: 180,
                heightMm: 40,
                anchor: .bottomLeft,
                layerID: page.defaultLayerID
            ),
        ]
        page.applyTextBoxSizing()
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: false)
        XCTAssertFalse(composed.hasBlockingOverflow)
        XCTAssertGreaterThan(composed.metrics.drawDistanceMm, 100)
        XCTAssertTrue(composed.gcode.contains("G1"))
    }

    func testRTLDetectionAndLayout() {
        let arabic = "مرحبا بك في كويل"
        XCTAssertTrue(TextLayoutEngine.detectRTL(arabic))
        var style = TextBoxStyle(fontSizeMm: 8, alignment: .right)
        style.isRTL = true
        let layout = TextLayoutEngine.layout(text: arabic, boxWidthMm: 80, boxHeightMm: 30, style: style)
        XCTAssertTrue(layout.isRTL)
        XCTAssertFalse(layout.missingGlyphs.isEmpty) // stick font lacks Arabic
    }

    func testMissingGlyphHandling() {
        let missing = TextLayoutEngine.missingGlyphs(in: "Hello ©®")
        XCTAssertTrue(missing.contains("©") || missing.contains("®"))
    }

    func testAnchorBasedPositioning() {
        var el = PageElement(
            name: "Box",
            kind: .shape(.rect),
            xMm: 25,
            yMm: 40,
            widthMm: 20,
            heightMm: 10,
            anchor: .center,
            layerID: UUID()
        )
        let origin = el.frameOriginPaper
        XCTAssertEqual(origin.x, 15, accuracy: 0.001)
        XCTAssertEqual(origin.y, 35, accuracy: 0.001)

        el.anchor = .topLeft
        let tl = el.frameOriginPaper
        XCTAssertEqual(tl.x, 25, accuracy: 0.001)
        XCTAssertEqual(tl.y, 30, accuracy: 0.001)
    }

    func testBedVersusPaperCoordinates() {
        let page = PageDocument(format: .placeCard, bedOriginX: 40, bedOriginY: 50)
        let bed = page.paperToBed(x: 25, y: 40)
        XCTAssertEqual(bed.x, 65, accuracy: 0.001)
        XCTAssertEqual(bed.y, 90, accuracy: 0.001)
        let paper = page.bedToPaper(x: bed.x, y: bed.y)
        XCTAssertEqual(paper.x, 25, accuracy: 0.001)
        XCTAssertEqual(paper.y, 40, accuracy: 0.001)

        var el = PageElement(
            name: "T",
            kind: .shape(.rect),
            xMm: 25,
            yMm: 40,
            widthMm: 10,
            heightMm: 10,
            anchor: .bottomLeft,
            layerID: page.defaultLayerID
        )
        var pageMut = page
        pageMut.editor.coordinateSpace = .bed
        LayoutTools.setDisplayPosition(element: &el, page: pageMut, x: 65, y: 90)
        XCTAssertEqual(el.xMm, 25, accuracy: 0.001)
        XCTAssertEqual(el.yMm, 40, accuracy: 0.001)
        let display = LayoutTools.displayPosition(element: el, page: pageMut)
        XCTAssertEqual(display.x, 65, accuracy: 0.001)
        XCTAssertEqual(display.y, 90, accuracy: 0.001)
    }

    func testTransformPersistenceRoundTrip() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 15, bedOriginY: 25)
        page.elements = [
            PageElement(
                name: "Rotated",
                kind: .textBox(text: "Hello path", style: TextBoxStyle(fontSizeMm: 8)),
                xMm: 30,
                yMm: 50,
                widthMm: 60,
                heightMm: 20,
                rotationDegrees: 15,
                scale: 1.25,
                anchor: .center,
                layerID: page.defaultLayerID
            ),
        ]
        page.editor.guides = [GuideLine(orientation: .vertical, positionMm: 105)]
        let project = QuillProject(page: page)
        let data = try project.jsonData()
        let loaded = try QuillProject.load(from: data)
        XCTAssertEqual(loaded.page.elements[0].xMm, 30, accuracy: 0.0001)
        XCTAssertEqual(loaded.page.elements[0].yMm, 50, accuracy: 0.0001)
        XCTAssertEqual(loaded.page.elements[0].rotationDegrees, 15, accuracy: 0.0001)
        XCTAssertEqual(loaded.page.elements[0].scale, 1.25, accuracy: 0.0001)
        XCTAssertEqual(loaded.page.elements[0].anchor, .center)
        XCTAssertEqual(loaded.page.editor.guides.count, 1)
        if case .textBox(let text, _) = loaded.page.elements[0].kind {
            XCTAssertEqual(text, "Hello path")
        } else {
            XCTFail("expected textBox")
        }
    }

    func testUndoRedoHistory() {
        var project = QuillProject()
        project.page.name = "A"
        let history = DocumentHistory()
        history.checkpoint(project)
        project.page.name = "B"
        history.checkpoint(project)
        project.page.name = "C"
        let undone = history.undo(current: project)!
        XCTAssertEqual(undone.page.name, "B")
        let redone = history.redo(current: undone)!
        XCTAssertEqual(redone.page.name, "C")
    }

    func testSnapping() {
        var page = PageDocument(format: .a5Landscape)
        page.editor.gridSpacingMm = 5
        page.editor.snapToGrid = true
        page.editor.snapToPaper = true
        page.editor.snapToObjects = false
        let snapped = SnapEngine.snapPosition(
            x: 12.2,
            y: 17.8,
            page: page,
            elementSize: (10, 10),
            disableSnap: false
        )
        XCTAssertEqual(snapped.x, 10, accuracy: 0.001)
        XCTAssertEqual(snapped.y, 20, accuracy: 0.001)
        let free = SnapEngine.snapPosition(
            x: 12.2,
            y: 17.8,
            page: page,
            elementSize: (10, 10),
            disableSnap: true
        )
        XCTAssertEqual(free.x, 12.2, accuracy: 0.001)
    }

    func testLayerOrdering() {
        var page = PageDocument()
        let a = page.defaultLayerID
        let b = page.addLayer(named: "Pen 2", pen: .marker)
        page.elements = [
            PageElement(name: "1", kind: .shape(.rect), layerID: a, zOrder: 0),
            PageElement(name: "2", kind: .shape(.rect), layerID: b, zOrder: 1),
        ]
        LayoutTools.bringToFront(&page.elements, id: page.elements[0].id)
        XCTAssertGreaterThan(page.elements[0].zOrder, page.elements[1].zOrder)
        var layers = page.layers.sorted { $0.order < $1.order }
        layers.swapAt(0, 1)
        for i in layers.indices { layers[i].order = i }
        page.layers = layers
        XCTAssertEqual(page.layers.sorted { $0.order < $1.order }.first?.id, b)
    }

    func testVariableDataOverflowPerRecord() {
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
        let batch = VariableData.makeBatch(
            template: page,
            fieldMap: [el.id: "{message}"],
            rows: parsed.rows
        )
        XCTAssertEqual(batch.pages.count, 2)
        XCTAssertFalse(batch.pages[0].overflows)
        XCTAssertTrue(batch.pages[1].overflows)
    }

    func testPreviewAndGeneratedPathParity() throws {
        var page = PageDocument(format: .a5Landscape, bedOriginX: 20, bedOriginY: 20)
        page.elements = [
            PageElement(
                name: "Parity",
                kind: .textBox(text: "Parity check path", style: TextBoxStyle(fontSizeMm: 8)),
                xMm: 20,
                yMm: 30,
                widthMm: 100,
                heightMm: 25,
                layerID: page.defaultLayerID
            ),
        ]
        let composed = try PageComposer.compose(page, profile: .ta4, optimize: false)
        let local = try PageComposer.plotJob(for: page.elements[0], profile: .ta4)
        let placed = PageComposer.transform(local, element: page.elements[0], page: page)
        XCTAssertEqual(placed.commands.count, composed.job.commands.count)
        for (a, b) in zip(placed.commands, composed.job.commands) {
            switch (a, b) {
            case (.move(let p), .move(let q)), (.line(let p), .line(let q)):
                XCTAssertEqual(p.x, q.x, accuracy: 0.001)
                XCTAssertEqual(p.y, q.y, accuracy: 0.001)
            case (.penChange, .penChange):
                break
            default:
                XCTFail("command mismatch")
            }
        }
        XCTAssertTrue(composed.gcode.contains("G1"))
    }

    func testLegacyTextMigratesToTextBox() {
        var page = PageDocument()
        page.elements = [
            PageElement(name: "Old", kind: .text("Hello", heightMm: 10), layerID: page.defaultLayerID),
        ]
        page.migrateLegacyText()
        if case .textBox(let t, let style) = page.elements[0].kind {
            XCTAssertEqual(t, "Hello")
            XCTAssertEqual(style.fontSizeMm, 10)
        } else {
            XCTFail("expected migration")
        }
    }

    func testAlignAndCentre() {
        var page = PageDocument(format: .a5Landscape)
        let id1 = UUID()
        let id2 = UUID()
        page.elements = [
            PageElement(id: id1, name: "A", kind: .shape(.rect), xMm: 10, yMm: 10, widthMm: 20, heightMm: 10, layerID: page.defaultLayerID),
            PageElement(id: id2, name: "B", kind: .shape(.rect), xMm: 50, yMm: 30, widthMm: 20, heightMm: 10, layerID: page.defaultLayerID),
        ]
        LayoutTools.align(&page.elements, ids: [id1, id2], page: page, horizontal: .left)
        XCTAssertEqual(page.elements[0].frameOriginPaper.x, page.elements[1].frameOriginPaper.x, accuracy: 0.001)
        LayoutTools.centreOnPage(&page.elements[0], page: page, horizontal: true, vertical: true)
        let origin = page.elements[0].frameOriginPaper
        XCTAssertEqual(origin.x + 10, page.format.widthMm / 2, accuracy: 0.05)
        XCTAssertEqual(origin.y + 5, page.format.heightMm / 2, accuracy: 0.05)
    }
}
