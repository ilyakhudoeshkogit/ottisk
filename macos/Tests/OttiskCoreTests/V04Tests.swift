import XCTest
@testable import OttiskCore

private let a4 = LayoutSize.a4
private func src(_ size: LayoutSize = a4, box: LayoutRect? = nil) -> LayoutSource {
    LayoutSource(pageSize: { _ in size }, contentBox: { _ in box })
}
private func pages(_ n: Int) -> [PageSlot] { (1...n).map { .page($0) } }
private func mm(_ pt: Double) -> Double { Units.mm(pt) }

final class LayoutGeometryTests: XCTestCase {
    func testGostLeftMarginIsAtLeast30mm() {
        // Word-документ со своими полями 20 мм: содержимое 170×257 мм.
        let content = LayoutRect(x: Units.pt(20), y: Units.pt(20), width: Units.pt(170), height: Units.pt(257))
        let s = PrintPreset.gost.apply(to: PrintSettings())
        let plan = LayoutPlanner.plan(slots: pages(3), source: src(box: content), settings: s)
        XCTAssertEqual(plan.sides.count, 3)
        for side in plan.sides {
            let p = side.placements[0]
            XCTAssertGreaterThanOrEqual(mm(p.target.minX), 30 - 0.01)
            XCTAssertLessThanOrEqual(mm(p.target.maxX), 210 - 15 + 0.01)
            XCTAssertLessThanOrEqual(mm(p.target.maxY), 297 - 20 + 0.01)
            XCTAssertGreaterThanOrEqual(mm(p.target.minY), 20 - 0.01)
            // Прижато к левому верхнему углу поля, текст не увеличен.
            XCTAssertEqual(mm(p.target.minX), 30, accuracy: 0.01)
            XCTAssertLessThanOrEqual(p.scale, 1)
            XCTAssertEqual(p.crop.width, content.width, accuracy: 1e-6)
            XCTAssertEqual(p.crop.x, content.x, accuracy: 1e-6)
        }
        // Номер на титуле не ставится, дальше 2 и 3 — внизу по центру.
        XCTAssertTrue(plan.sides[0].labels.isEmpty)
        XCTAssertEqual(plan.sides[1].labels.map(\.text), ["2"])
        XCTAssertEqual(plan.sides[2].labels.first?.alignment, .center)
        XCTAssertEqual(mm(plan.sides[2].labels[0].y), 10, accuracy: 0.01)
        XCTAssertEqual(plan.sides[2].labels[0].x, plan.sides[2].area.midX, accuracy: 0.01)
    }

    func testGostAddModeKeepsWholePageInsideMargins() {
        var s = PrintPreset.gost.apply(to: PrintSettings())
        s.marginsAdd = true
        let content = LayoutRect(x: 50, y: 50, width: 100, height: 100)
        let plan = LayoutPlanner.plan(slots: pages(1), source: src(box: content), settings: s)
        let p = plan.sides[0].placements[0]
        XCTAssertEqual(p.crop, LayoutRect(size: a4)) // вся страница со своими полями
        XCTAssertTrue(p.target.isInside(plan.sides[0].area))
        XCTAssertGreaterThanOrEqual(mm(p.target.minX), 30 - 0.01)
    }

    func testBsuirNumberBottomRight() {
        let s = PrintPreset.bsuir.apply(to: PrintSettings())
        let plan = LayoutPlanner.plan(slots: pages(2), source: src(), settings: s)
        let label = plan.sides[1].labels[0]
        XCTAssertEqual(label.alignment, .right)
        XCTAssertEqual(mm(label.x), 210 - 15, accuracy: 0.01)
    }

    func testNumberingTiedToDocumentPage() {
        var n = PageNumbering(enabled: true, startAt: 5, skipFirst: 1)
        XCTAssertNil(n.label(forPage: 1))
        XCTAssertEqual(n.label(forPage: 2), "6")
        n.enabled = false
        XCTAssertNil(n.label(forPage: 2))
        // Перепечатка одной страницы — номер тот же.
        var s = PrintPreset.gost.apply(to: PrintSettings())
        s.numbering.startAt = 1
        let plan = LayoutPlanner.plan(slots: [.page(7)], source: src(), settings: s)
        XCTAssertEqual(plan.sides[0].labels.map(\.text), ["7"])
    }

    func testGutterAndMirror() {
        var s = PrintSettings()
        s.margins = PageMargins(all: 10)
        s.gutter = 8
        s.mirrorMargins = true
        s.manualDuplex = true
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: false).left, 18)
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: false).right, 10)
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: true).left, 10)
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: true).right, 18)
        s.gutterEdge = .top
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: false).top, 18)
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: true).bottom, 18)
        s.mirrorMargins = false
        XCTAssertEqual(LayoutPlanner.effectiveMargins(s, isBack: true).top, 18)
        // В раскладке: обороты помечены, поле переплёта на оборотах справа.
        s.gutterEdge = .left
        s.mirrorMargins = true
        let plan = LayoutPlanner.plan(slots: pages(2), source: src(), settings: s)
        XCTAssertFalse(plan.sides[0].isBack)
        XCTAssertTrue(plan.sides[1].isBack)
        XCTAssertEqual(mm(plan.sides[0].area.minX), 18, accuracy: 0.01)
        XCTAssertEqual(mm(plan.sides[1].area.minX), 10, accuracy: 0.01)
    }

    func testScaleModes() {
        let small = LayoutSize(width: 200, height: 300)
        var s = PrintSettings()
        s.scaleMode = .actual
        var p = LayoutPlanner.plan(slots: pages(1), source: src(small), settings: s).sides[0].placements[0]
        XCTAssertEqual(p.scale, 1)
        XCTAssertEqual(p.target.midX, a4.width / 2, accuracy: 0.01)
        XCTAssertEqual(p.target.midY, a4.height / 2, accuracy: 0.01)
        s.scaleMode = .custom
        s.customScale = 150
        p = LayoutPlanner.plan(slots: pages(1), source: src(small), settings: s).sides[0].placements[0]
        XCTAssertEqual(p.scale, 1.5)
        s.scaleMode = .fit
        p = LayoutPlanner.plan(slots: pages(1), source: src(small), settings: s).sides[0].placements[0]
        XCTAssertEqual(p.scale, min(a4.width / 200, a4.height / 300), accuracy: 1e-6)
        s.customScale = 5000
        s.scaleMode = .custom
        p = LayoutPlanner.plan(slots: pages(1), source: src(small), settings: s).sides[0].placements[0]
        XCTAssertEqual(p.scale, 4)
    }

    func testAutoOrientationForLandscapePage() {
        let land = LayoutSize(width: 842, height: 595)
        let plan = LayoutPlanner.plan(slots: pages(1), source: src(land), settings: PrintSettings())
        XCTAssertTrue(plan.sides[0].size.isLandscape)
        var s = PrintSettings()
        s.orientation = .portrait
        XCTAssertFalse(LayoutPlanner.plan(slots: pages(1), source: src(land), settings: s).sides[0].size.isLandscape)
    }

    func testTwoUpIsLandscapeFourUpIsPortrait() {
        var s = PrintSettings()
        s.pagesPerSheet = 2
        let two = LayoutPlanner.plan(slots: pages(3), source: src(), settings: s)
        XCTAssertEqual(two.sides.count, 2)
        XCTAssertTrue(two.sides[0].size.isLandscape)
        XCTAssertEqual(two.sides[1].placements.count, 2)
        XCTAssertEqual(two.sides[1].placements[1].slot, .blank)
        s.pagesPerSheet = 4
        let four = LayoutPlanner.plan(slots: pages(4), source: src(), settings: s)
        XCTAssertFalse(four.sides[0].size.isLandscape)
        for p in four.sides[0].placements { XCTAssertTrue(p.target.isInside(p.cell)) }
    }

    func testNUpOrder() {
        let area = LayoutRect(x: 0, y: 0, width: 200, height: 200)
        let z = LayoutPlanner.gridCells(area: area, columns: 2, rows: 2, order: .rows)
        let n = LayoutPlanner.gridCells(area: area, columns: 2, rows: 2, order: .columns)
        // Z: 1 — левый верх, 2 — правый верх. N: 2 — левый низ.
        XCTAssertLessThan(z[0].minX, z[1].minX)
        XCTAssertEqual(z[0].minY, z[1].minY)
        XCTAssertEqual(n[0].minX, n[1].minX)
        XCTAssertGreaterThan(n[0].minY, n[1].minY)
        XCTAssertEqual(z[0], n[0])
        XCTAssertEqual(z[3], n[3])
    }

    func testRepeatEachTwoCopiesOnOneSheet() {
        let slots = LogicalPages.sequence(selected: [1, 2], repeatEach: 2)
        XCTAssertEqual(slots, [.page(1), .page(1), .page(2), .page(2)])
        var s = PrintSettings()
        s.pagesPerSheet = 2
        let plan = LayoutPlanner.plan(slots: slots, source: src(), settings: s)
        XCTAssertEqual(plan.sides.count, 2)
        XCTAssertEqual(plan.sides[0].placements.map(\.slot), [.page(1), .page(1)])
    }

    func testParityAndBlanks() {
        XCTAssertEqual(LogicalPages.sequence(selected: [1, 2, 3, 4, 5], parity: .odd), [.page(1), .page(3), .page(5)])
        XCTAssertEqual(LogicalPages.sequence(selected: [2, 3, 4], parity: .even), [.page(2), .page(4)])
        XCTAssertEqual(LogicalPages.sequence(selected: [1, 2, 3, 4, 5], blankEvery: 2),
                       [.page(1), .page(2), .blank, .page(3), .page(4), .blank, .page(5)])
        // В конце разделитель не нужен.
        XCTAssertEqual(LogicalPages.sequence(selected: [1, 2], blankEvery: 2), [.page(1), .page(2)])
    }

    func testReverseOrderInPlan() {
        var s = PrintSettings()
        s.reverseOrder = true
        let plan = LayoutPlanner.plan(slots: pages(3), source: src(), settings: s)
        XCTAssertEqual(plan.sides.map { $0.placements[0].slot }, [.page(3), .page(2), .page(1)])
        // При ручной двусторонней порядок задаёт план проходов, не «обратный порядок».
        s.manualDuplex = true
        let duplex = LayoutPlanner.plan(slots: pages(3), source: src(), settings: s)
        XCTAssertEqual(duplex.sides.map { $0.placements[0].slot }, [.page(1), .page(2), .page(3)])
    }

    func testTrimWhiteUsesContentBox() {
        var s = PrintSettings()
        s.trimWhite = true
        s.pagesPerSheet = 4
        let box = LayoutRect(x: 60, y: 60, width: 400, height: 700)
        let plan = LayoutPlanner.plan(slots: pages(4), source: src(box: box), settings: s)
        XCTAssertEqual(plan.sides[0].placements[0].crop, box)
        // Без обрезки — вся страница.
        s.trimWhite = false
        XCTAssertEqual(LayoutPlanner.plan(slots: pages(1), source: src(box: box), settings: s).sides[0].placements[0].crop,
                       LayoutRect(size: a4))
    }

    func testCellBordersAndNumbersInNUp() {
        var s = PrintSettings()
        s.pagesPerSheet = 2
        s.cellBorders = true
        s.numbering = PageNumbering(enabled: true)
        let side = LayoutPlanner.plan(slots: pages(2), source: src(), settings: s).sides[0]
        XCTAssertEqual(side.lines.count, 8)
        XCTAssertEqual(side.labels.map(\.text), ["1", "2"])
        for p in side.placements { XCTAssertGreaterThan(p.target.minY, side.labels[0].y) }
    }

    func testSlidesWithNotes() {
        let slide = LayoutSize(width: 720, height: 405)
        let s = PrintPreset.slides.apply(to: PrintSettings())
        let side = LayoutPlanner.plan(slots: pages(4), source: src(slide), settings: s).sides[0]
        XCTAssertFalse(side.size.isLandscape)
        XCTAssertEqual(side.placements.count, 4)
        // Слайды в левой части, линии — справа от них.
        let maxSlideX = side.placements.map(\.cell.maxX).max()!
        let noteLines = side.lines.filter { $0.width < 0.45 }
        XCTAssertFalse(noteLines.isEmpty)
        XCTAssertTrue(noteLines.allSatisfy { $0.x1 > maxSlideX })
        XCTAssertLessThan(side.placements[0].target.minY, side.placements[0].cell.maxY + 0.01)
        XCTAssertGreaterThan(side.placements[0].target.midY, side.placements[1].target.midY)
    }

    func testEskdFrameAndTitleBlock() {
        let s = PrintPreset.eskdFrame.apply(to: PrintSettings())
        let side = LayoutPlanner.plan(slots: pages(3), source: src(), settings: s).sides[2]
        // Рамка: 20 мм слева, 5 мм справа.
        let verticals = side.lines.filter { abs($0.x1 - $0.x2) < 0.01 }
        XCTAssertTrue(verticals.contains { abs(mm($0.x1) - 20) < 0.01 })
        XCTAssertTrue(verticals.contains { abs(mm($0.x1) - 205) < 0.01 })
        // Штамп 185×15: левая граница на 20 мм, верх на 20 мм от низа листа.
        XCTAssertTrue(side.lines.contains { abs(mm($0.y1) - 20) < 0.01 && abs(mm($0.y2) - 20) < 0.01 })
        // Номер листа — в графе «Лист», отдельной цифры внизу по центру нет.
        XCTAssertTrue(side.labels.contains { $0.text == "3" && $0.fontSize == 10 })
        XCTAssertTrue(side.labels.contains { $0.text == "Лист" })
        // Текст не заходит в рамку и штамп (ГОСТ Р 2.105-2019, 5.1.3).
        let p = side.placements[0]
        XCTAssertGreaterThanOrEqual(mm(p.target.minX), 23 - 0.01)
        XCTAssertGreaterThanOrEqual(mm(p.target.minY), 30 - 0.01)
        XCTAssertEqual(EskdForm2a.columnsMM.reduce(0, +), 185)
    }

    func testFileHeader() {
        var s = PrintSettings()
        s.fileHeader = true
        let plan = LayoutPlanner.plan(slots: pages(2), source: LayoutSource(pageSize: { _ in a4 }, headerText: "Курсовая.pdf · 14.11.2026"),
                                      settings: s)
        XCTAssertEqual(plan.sides[1].labels.map(\.text), ["Курсовая.pdf · 14.11.2026", "2 / 2"])
        XCTAssertGreaterThanOrEqual(LayoutPlanner.effectiveMargins(s, isBack: false).top, 10)
    }

    func testBookletSidesOrderAndBacks() {
        var s = PrintSettings()
        s.booklet = true
        let plan = LayoutPlanner.plan(slots: pages(8), source: src(), settings: s)
        XCTAssertEqual(plan.sides.count, 4)
        XCTAssertTrue(plan.sides[0].size.isLandscape)
        XCTAssertEqual(plan.sides[0].placements.map(\.slot), [.page(8), .page(1)])
        XCTAssertEqual(plan.sides[1].placements.map(\.slot), [.page(2), .page(7)])
        XCTAssertEqual(plan.sides.map(\.isBack), [false, true, false, true])
        XCTAssertEqual(plan.sheetCount(twoSided: true), 2)
        // Пустые места в брошюре из 5 страниц.
        let five = LayoutPlanner.plan(slots: pages(5), source: src(), settings: s)
        XCTAssertEqual(five.sides[0].placements.map(\.slot), [.blank, .page(1)])
    }

    func testContentBoundsDetection() {
        let w = 10, h = 8
        var gray = [UInt8](repeating: 255, count: w * h)
        // Тёмный блок: столбцы 2…5, строки (сверху) 1…3.
        for y in 1...3 { for x in 2...5 { gray[y * w + x] = 0 } }
        // Пылинка — один пиксель, игнорируется.
        gray[7 * w + 9] = 0
        let r = ContentBounds.detect(gray: gray, width: w, height: h)
        XCTAssertEqual(r, LayoutRect(x: 2, y: 4, width: 4, height: 3))
        XCTAssertNil(ContentBounds.detect(gray: [UInt8](repeating: 255, count: w * h), width: w, height: h))
        let page = ContentBounds.toPage(r!, pixelsPerPoint: 2, page: LayoutSize(width: 5, height: 4), paddingMM: 0)
        XCTAssertEqual(page, LayoutRect(x: 1, y: 2, width: 2, height: 1.5))
        let unified = ContentBounds.unified([1: LayoutRect(x: 10, y: 10, width: 10, height: 10),
                                             2: LayoutRect(x: 5, y: 20, width: 10, height: 10)],
                                            sizes: [1: a4, 2: a4, 3: a4])
        XCTAssertEqual(unified[3], LayoutRect(x: 5, y: 10, width: 15, height: 20))
    }

    func testMediaSheetSize() {
        XCTAssertEqual(LayoutSize.sheet(forMedia: nil), .a4)
        XCTAssertEqual(LayoutSize.sheet(forMedia: "iso_a5_148x210mm"), .a5)
        XCTAssertEqual(LayoutSize.sheet(forMedia: "Letter"), .letter)
    }

    func testScanEnhance() {
        XCTAssertEqual(ScanEnhance.contrast(level: 0), 1)
        XCTAssertEqual(ScanEnhance.contrast(level: 9), 1.9, accuracy: 1e-9)
        XCTAssertEqual(ScanEnhance.thickenRadius(level: 2, dpi: 254), 1, accuracy: 1e-9)
    }
}

final class V04SettingsTests: XCTestCase {
    func testNeedsComposition() {
        XCTAssertFalse(PrintSettings().needsComposition)
        XCTAssertFalse(PrintPreset.economy.apply(to: PrintSettings()).needsComposition)
        XCTAssertFalse(PrintPreset.manualDuplex.apply(to: PrintSettings()).needsComposition)
        for p in [PrintPreset.gost, .bsuir, .eskdFrame, .lectureNotes, .bookletManual, .paperSaver, .signDocument, .slides, .passport] {
            XCTAssertTrue(p.apply(to: PrintSettings()).needsComposition, p.rawValue)
        }
    }

    func testPresetsAreDistinctAndMatch() {
        for p in PrintPreset.allCases {
            let s = p.apply(to: PrintSettings())
            XCTAssertEqual(PrintPreset.matching(s), p, p.rawValue)
        }
        XCTAssertEqual(PrintPreset.presets(in: .study).count, 9)
    }

    func testSignDocumentKeepsUserRange() {
        var base = PrintSettings()
        XCTAssertEqual(PrintPreset.signDocument.apply(to: base).pageRange, "1")
        base.pageRange = "2-3"
        XCTAssertEqual(PrintPreset.signDocument.apply(to: base).pageRange, "2-3")
    }

    func testCustomPresetRoundTripsAllNewFields() throws {
        var s = PrintPreset.gost.apply(to: PrintSettings())
        s.gutter = 7
        s.gutterEdge = .top
        s.mirrorMargins = true
        s.parity = .even
        s.repeatEach = 2
        s.blankEvery = 3
        s.blankBetweenCopies = true
        s.fileHeader = true
        s.cellBorders = true
        s.nUpOrder = .columns
        s.trimWhite = true
        s.thickenLines = 2
        s.contrastBoost = 3
        s.eskdFrame = true
        s.eskdTitleBlock = true
        s.eskdDesignation = "ГУИР.400201.001 ПЗ"
        s.slideNotes = true
        s.tonerDensity = "3"
        s.scaleMode = .custom
        s.customScale = 93
        s.marginsAdd = true
        s.numbering = PageNumbering(enabled: true, startAt: 4, skipFirst: 3, position: .topRight)
        var lib = PresetLibrary()
        try lib.add(name: "Курсовая", settings: s)
        let back = try PresetLibrary.decode(lib.encode())
        var expected = s
        expected.pageRange = ""
        XCTAssertEqual(back.presets[0].settings, expected)
    }

    func testOldPresetFitToPageFalseBecomesActual() throws {
        let json = #"{"version":1,"presets":[{"id":"\#(UUID().uuidString)","name":"Старый","symbol":"star","settings":{"fitToPage":false}}]}"#
        let lib = try PresetLibrary.decode(Data(json.utf8))
        XCTAssertEqual(lib.presets[0].settings.scaleMode, .actual)
        XCTAssertEqual(lib.presets[0].settings.margins, .zero)
    }

    func testComposedLPArguments() {
        var s = PrintPreset.paperSaver.apply(to: PrintSettings())
        s.reverseOrder = true
        s.orientation = .landscape
        s.tonerDensity = "Dark"
        let density = PrinterOption(key: "CNTonerDensity", label: "Toner Density", choices: ["Light", "Normal", "Dark"], defaultChoice: "Normal")
        let driver = DriverOptionMatcher.resolve([density])
        XCTAssertEqual(driver.density?.key, "CNTonerDensity")
        let args = LPArgumentsBuilder.arguments(printer: "P", settings: s, driver: driver, title: nil, pages: nil,
                                                files: ["/a.pdf"], composed: true)
        XCTAssertEqual(args, ["-d", "P", "-o", "print-scaling=none", "-o", "CNTonerDensity=Dark", "--", "/a.pdf"])
        // Неизвестное значение плотности не уходит в lp.
        s.tonerDensity = "Ultra"
        XCTAssertFalse(LPArgumentsBuilder.arguments(printer: "P", settings: s, driver: driver, title: nil, pages: nil,
                                                    files: ["/a.pdf"], composed: true).contains { $0.hasPrefix("CNTonerDensity") })
    }

    func testDensitySnapshotRoundTrip() throws {
        let density = PrinterOption(key: "Density", label: "Density", choices: ["1", "2", "3"], defaultChoice: "2")
        let resolved = ResolvedDriverOptions(density: density)
        let snap = DriverSnapshot(resolved)
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(DriverSnapshot.self, from: data)
        XCTAssertEqual(back.resolved.density?.key, "Density")
        XCTAssertEqual(back.resolved.density?.choices, ["1", "2", "3"])
    }
}

/// Ручная двусторонняя на MF3010: проверяем порядок на модели пачки.
///
/// Модель механики (по руководству MF3010: бумага в кассете лицевой/печатной стороной вверх,
/// выход сверху лицом вниз): листы прохода 1 ложатся в выходной лоток друг на друга,
/// сверху оказывается последний. Пачку разворачивают в плоскости стола на 180°, НЕ переворачивая,
/// и кладут в кассету — чистые стороны смотрят вверх, первым подаётся верхний (последний) лист.
final class ManualDuplexOrderTests: XCTestCase {
    private func simulate(sideCount: Int, copies: Int = 1) -> [(front: PageSlot, back: PageSlot)] {
        let plan = DuplexPlanner.sidesPlan(sideCount: sideCount, reverseBacks: true, copies: copies)
        // Выходной лоток: печатаем по порядку, каждый новый лист ложится сверху.
        var stack: [PageSlot] = []          // индекс 0 — низ пачки
        for front in plan.fronts { stack.append(front) }
        // Кассета: подаётся верхний лист.
        var sheets: [(front: PageSlot, back: PageSlot)] = []
        var feed = stack
        for back in plan.backs {
            guard let sheetFront = feed.popLast() else { XCTFail("обротов больше, чем листов"); break }
            sheets.append((sheetFront, back))
        }
        XCTAssertTrue(feed.isEmpty, "все листы должны получить оборот (хотя бы пустой)")
        return sheets
    }

    func testEveryBackLandsOnItsFront() {
        for count in 1...11 {
            for copies in 1...3 {
                let plan = DuplexPlanner.sidesPlan(sideCount: count, copies: copies)
                XCTAssertEqual(plan.sheetCount, (count + 1) / 2 * copies)
                // Проход 1 — только нечётные стороны.
                for slot in plan.fronts {
                    if case .page(let n) = slot { XCTAssertEqual(n % 2, 1) }
                }
                guard plan.needsSecondPass else {
                    XCTAssertEqual(count, 1)
                    continue
                }
                for pair in simulate(sideCount: count, copies: copies) {
                    switch (pair.front, pair.back) {
                    case (.page(let f), .page(let b)): XCTAssertEqual(b, f + 1, "стороны \(count), копий \(copies)")
                    case (.page(let f), .blank): XCTAssertEqual(f, count, "пустой оборот только у последнего листа")
                    default: XCTFail("неожиданная пара \(pair)")
                    }
                }
            }
        }
    }

    func testOddCountAddsBlankFirstInSecondPass() {
        let plan = DuplexPlanner.sidesPlan(sideCount: 5)
        XCTAssertEqual(plan.fronts, [.page(1), .page(3), .page(5)])
        // Первым из кассеты пойдёт лист 5 — ему пустой оборот, затем 4 и 2.
        XCTAssertEqual(plan.backs, [.blank, .page(4), .page(2)])
    }

    func testPresetTwoSidedComposesWithoutNUp() {
        // Пресет «С двух сторон» не требует своего PDF: стороны = страницы документа.
        let s = PrintPreset.manualDuplex.apply(to: PrintSettings())
        XCTAssertTrue(s.manualDuplex)
        let plan = LayoutPlanner.plan(slots: pages(5), source: src(), settings: s)
        XCTAssertEqual(plan.sides.count, 5)
        XCTAssertEqual(plan.sheetCount(twoSided: true), 3)
        XCTAssertEqual(plan.sides.map(\.isBack), [false, true, false, true, false])
    }

    func testBookletPasses() {
        let plan = DuplexPlanner.bookletPasses(sideCount: 4, reverseBacks: true, copies: 1)
        XCTAssertEqual(plan.fronts, [.page(1), .page(3)])
        XCTAssertEqual(plan.backs, [.page(4), .page(2)])
        XCTAssertEqual(DuplexPlanner.bookletPasses(sideCount: 4, reverseBacks: false, copies: 2).backs,
                       [.page(2), .page(4), .page(2), .page(4)])
    }

    func testGateWaitsForQueue() {
        var gate = DuplexGate(frontJobID: "MF-7")
        XCTAssertFalse(gate.canPrintBacks)
        let job = PrintJob(id: "MF-7", printer: "MF", number: 7, user: "ilya", sizeBytes: nil, dateText: "")
        gate.update(queue: [job])
        XCTAssertFalse(gate.canPrintBacks)
        gate.update(queue: [])
        XCTAssertTrue(gate.canPrintBacks)
        var fast = DuplexGate(frontJobID: "MF-8")
        fast.update(queue: [job])   // другое задание, наше уже ушло
        XCTAssertTrue(fast.canPrintBacks)
        var tracked = DuplexGate(frontJobID: "MF-9")
        tracked.markFinished()
        XCTAssertTrue(tracked.canPrintBacks)
    }
}
