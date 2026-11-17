import XCTest
@testable import OttiskCore

final class CustomPresetTests: XCTestCase {
    private func settings(copies: Int = 1, perSheet: Int = 1, toner: Bool = false, range: String = "") -> PrintSettings {
        var s = PrintSettings()
        s.copies = copies
        s.pagesPerSheet = perSheet
        s.tonerSave = toner
        s.pageRange = range
        return s
    }

    func testAddValidatesNames() throws {
        var lib = PresetLibrary()
        let p = try lib.add(name: "  Счета  ", settings: settings(copies: 2, range: "1-3"))
        XCTAssertEqual(p.name, "Счета")
        XCTAssertEqual(p.settings.pageRange, "", "диапазон в пресет не сохраняется")
        XCTAssertEqual(p.settings.copies, 2)
        XCTAssertThrowsError(try lib.add(name: "   ", settings: settings())) { XCTAssertEqual($0 as? PresetLibrary.ValidationError, .emptyName) }
        XCTAssertThrowsError(try lib.add(name: "счета", settings: settings())) { XCTAssertEqual($0 as? PresetLibrary.ValidationError, .duplicate("счета")) }
        XCTAssertThrowsError(try lib.add(name: "Черновик", settings: settings()), "нельзя повторять встроенный пресет")
        XCTAssertThrowsError(try lib.add(name: String(repeating: "я", count: 33), settings: settings())) {
            XCTAssertEqual($0 as? PresetLibrary.ValidationError, .tooLong(max: 32))
        }
        XCTAssertEqual(lib.presets.count, 1)
    }

    func testRenameUpdateDelete() throws {
        var lib = PresetLibrary()
        let a = try lib.add(name: "Билеты", settings: settings(copies: 2))
        let b = try lib.add(name: "Конспекты", settings: settings(perSheet: 4))
        try lib.rename(a.id, to: "Билеты") // то же имя у себя — можно
        try lib.rename(a.id, to: "Посадочные")
        XCTAssertThrowsError(try lib.rename(a.id, to: "конспекты"))
        XCTAssertEqual(lib.preset(a.id)?.name, "Посадочные")

        try lib.update(b.id, settings: settings(perSheet: 2, toner: true, range: "5"))
        XCTAssertEqual(lib.preset(b.id)?.settings.pagesPerSheet, 2)
        XCTAssertEqual(lib.preset(b.id)?.settings.pageRange, "")
        try lib.setSymbol(b.id, "book")
        XCTAssertEqual(lib.preset(b.id)?.symbol, "book")

        lib.delete(a.id)
        XCTAssertNil(lib.preset(a.id))
        XCTAssertThrowsError(try lib.rename(a.id, to: "X")) { XCTAssertEqual($0 as? PresetLibrary.ValidationError, .notFound) }
        XCTAssertThrowsError(try lib.update(a.id, settings: settings()))
    }

    func testApplyKeepsRangeAndMatching() throws {
        var lib = PresetLibrary()
        let p = try lib.add(name: "Эконом 4", settings: settings(perSheet: 4, toner: true))
        let current = settings(copies: 3, range: "2-5")
        let applied = p.apply(to: current)
        XCTAssertEqual(applied.pagesPerSheet, 4)
        XCTAssertTrue(applied.tonerSave)
        XCTAssertEqual(applied.copies, 1)
        XCTAssertEqual(applied.pageRange, "2-5")
        XCTAssertEqual(lib.matching(applied)?.id, p.id)
        XCTAssertNil(lib.matching(current))
    }

    func testMove() throws {
        var lib = PresetLibrary()
        let a = try lib.add(name: "A", settings: settings())
        let b = try lib.add(name: "B", settings: settings())
        let c = try lib.add(name: "C", settings: settings())
        lib.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(lib.presets.map(\.id), [b.id, c.id, a.id])
        lib.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(lib.presets.map(\.id), [a.id, b.id, c.id])
    }

    func testJSONRoundTripAndTolerance() throws {
        var lib = PresetLibrary()
        try lib.add(name: "Счета", symbol: "creditcard", settings: settings(copies: 2, toner: true))
        try lib.add(name: "Книжка", settings: { var s = PrintSettings(); s.booklet = true; return s }())
        let data = try lib.encode()
        XCTAssertEqual(try PresetLibrary.decode(data), lib)

        // Старый файл без новых полей + один битый пресет + дубликат id.
        let id = UUID().uuidString
        let json = """
        {"version":1,"presets":[
          {"id":"\(id)","name":"Старый","symbol":"star","settings":{"copies":3}},
          {"id":"\(id)","name":"Дубль","symbol":"star","settings":{}},
          {"name":"Без id","settings":{}},
          {"id":"\(UUID().uuidString)","name":"Странная ориентация","symbol":"star","settings":{"orientation":"diagonal"}}
        ]}
        """
        let loaded = try PresetLibrary.decode(Data(json.utf8))
        XCTAssertEqual(loaded.presets.map(\.name), ["Старый", "Странная ориентация"])
        XCTAssertEqual(loaded.presets[0].settings.copies, 3)
        XCTAssertEqual(loaded.presets[0].settings.fitToPage, true)
        XCTAssertFalse(loaded.presets[0].settings.booklet)
        XCTAssertEqual(loaded.presets[1].settings.orientation, .auto)
        XCTAssertThrowsError(try PresetLibrary.decode(Data("not json".utf8)))
    }
}

final class BookletTests: XCTestCase {
    func testEightPages() {
        let plan = BookletPlanner.plan(pages: Array(1...8), reverseBacks: false)
        XCTAssertEqual(plan.sheetCount, 2)
        XCTAssertEqual(plan.sheets[0].front, BookletSide(left: .page(8), right: .page(1)))
        XCTAssertEqual(plan.sheets[0].back, BookletSide(left: .page(2), right: .page(7)))
        XCTAssertEqual(plan.sheets[1].front, BookletSide(left: .page(6), right: .page(3)))
        XCTAssertEqual(plan.sheets[1].back, BookletSide(left: .page(4), right: .page(5)))
        XCTAssertEqual(plan.backs.first, plan.sheets[0].back)
    }

    func testPaddingWithBlanksAtTheEnd() {
        let plan = BookletPlanner.plan(pages: [1, 2, 3, 4, 5], reverseBacks: false)
        XCTAssertEqual(BookletPlanner.paddedCount(5), 8)
        XCTAssertEqual(plan.sheets[0].front, BookletSide(left: .blank, right: .page(1)))
        XCTAssertEqual(plan.sheets[0].back, BookletSide(left: .page(2), right: .blank))
        XCTAssertEqual(plan.sheets[1].front, BookletSide(left: .blank, right: .page(3)))
        XCTAssertEqual(plan.sheets[1].back, BookletSide(left: .page(4), right: .page(5)))
    }

    func testEveryPageExactlyOnce() {
        for n in 1...41 {
            let pages = Array(1...n)
            let plan = BookletPlanner.plan(pages: pages)
            let all = plan.sheets.flatMap { [$0.front.left, $0.front.right, $0.back.left, $0.back.right] }
            XCTAssertEqual(all.count, BookletPlanner.paddedCount(n))
            let printed = all.compactMap { slot -> Int? in if case .page(let p) = slot { return p } else { return nil } }
            XCTAssertEqual(printed.sorted(), pages, "n=\(n)")
            XCTAssertEqual(plan.sheetCount, BookletPlanner.sheetCount(pageCount: n))
        }
    }

    func testSelectedPagesAndReverse() {
        let plan = BookletPlanner.plan(pages: [3, 4, 5, 6, 7, 8, 9, 10], reverseBacks: true)
        XCTAssertEqual(plan.fronts[0], BookletSide(left: .page(10), right: .page(3)))
        // Обороты в обратном порядке: сначала оборот второго листа.
        XCTAssertEqual(plan.backs[0], BookletSide(left: .page(6), right: .page(7)))
        XCTAssertEqual(plan.backs[1], BookletSide(left: .page(4), right: .page(9)))
        XCTAssertTrue(BookletPlanner.plan(pages: []).sheets.isEmpty)
    }

    func testSheetCountInSettings() {
        var s = PrintSettings()
        s.booklet = true
        XCTAssertEqual(s.sheetCount(selectedPages: 9), 3)
        XCTAssertEqual(s.sheetCount(selectedPages: 1), 1)
    }
}

final class WatermarkTests: XCTestCase {
    func testActiveAndClamp() {
        XCTAssertFalse(Watermark(text: "   ").isActive)
        XCTAssertTrue(Watermark(text: "КОПИЯ").isActive)
        XCTAssertEqual(Watermark(text: "x", opacity: 2).clampedOpacity, 0.6)
        XCTAssertEqual(Watermark(text: "x", opacity: 0).clampedOpacity, 0.05)
    }

    func testFontFitsPage() {
        let a4w = 595.0, a4h = 842.0
        let short = Watermark(text: "КОПИЯ").fontSize(pageWidth: a4w, pageHeight: a4h)
        let long = Watermark(text: "КОНФИДЕНЦИАЛЬНО — НЕ РАСПРОСТРАНЯТЬ").fontSize(pageWidth: a4w, pageHeight: a4h)
        XCTAssertGreaterThan(short, long)
        XCTAssertLessThanOrEqual(short, 160)
        XCTAssertGreaterThanOrEqual(long, 12)
        // Ширина текста вдоль диагонали не больше диагонали страницы.
        let width = short * 0.62 * 5
        XCTAssertLessThan(width, (a4w * a4w + a4h * a4h).squareRoot())
        // Горизонтальный знак ограничен шириной страницы.
        let flat = Watermark(text: "ОБРАЗЕЦ", angle: 0).fontSize(pageWidth: a4w, pageHeight: a4h)
        XCTAssertLessThanOrEqual(flat * 0.62 * 7, a4w)
    }
}

final class OttiskLinkTests: XCTestCase {
    func testParse() throws {
        let url = URL(string: "ottisk://print?file=/Users/ilya/Documents/%D0%A1%D1%87%D1%91%D1%82.pdf&preset=economy")!
        XCTAssertEqual(try OttiskLink.parse(url), .open(files: [URL(fileURLWithPath: "/Users/ilya/Documents/Счёт.pdf")], preset: "economy"))
        let two = URL(string: "ottisk://print?file=/tmp/a.pdf&file=file:///tmp/b%20c.png")!
        XCTAssertEqual(try OttiskLink.parse(two), .open(files: [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b c.png")], preset: nil))
        XCTAssertEqual(try OttiskLink.parse(URL(string: "OTTISK://open?path=/tmp/x.pdf")!),
                       .open(files: [URL(fileURLWithPath: "/tmp/x.pdf")], preset: nil))
    }

    func testErrors() {
        XCTAssertThrowsError(try OttiskLink.parse(URL(string: "https://print?file=/a.pdf")!)) { XCTAssertEqual($0 as? OttiskLink.ParseError, .wrongScheme) }
        XCTAssertThrowsError(try OttiskLink.parse(URL(string: "ottisk://delete?file=/a.pdf")!)) { XCTAssertEqual($0 as? OttiskLink.ParseError, .unknownAction("delete")) }
        XCTAssertThrowsError(try OttiskLink.parse(URL(string: "ottisk://print")!)) { XCTAssertEqual($0 as? OttiskLink.ParseError, .noFiles) }
        XCTAssertThrowsError(try OttiskLink.parse(URL(string: "ottisk://print?file=relative.pdf")!)) {
            XCTAssertEqual($0 as? OttiskLink.ParseError, .notAbsolute("relative.pdf"))
        }
    }

    func testMakeRoundTrip() throws {
        let url = try XCTUnwrap(OttiskLink.make(files: ["/tmp/Мой файл.pdf"], preset: "draft"))
        XCTAssertTrue(url.absoluteString.hasPrefix("ottisk://print?file="))
        XCTAssertEqual(try OttiskLink.parse(url), .open(files: [URL(fileURLWithPath: "/tmp/Мой файл.pdf")], preset: "draft"))
    }
}

final class JobTrackerTests: XCTestCase {
    private func job(_ id: String) -> PrintJob {
        PrintJob(id: id, printer: "Canon_MF3010", number: Int(id.split(separator: "-").last!), user: "ilya", sizeBytes: nil, dateText: "")
    }

    func testFinishedWhenGone() {
        var t = JobCompletionTracker()
        t.watch("Canon_MF3010-12", title: "Счёт.pdf")
        t.watch("Canon_MF3010-11", title: "Билет.pdf")
        XCTAssertEqual(t.update(with: [job("Canon_MF3010-11"), job("Canon_MF3010-12")]), [])
        XCTAssertEqual(t.update(with: [job("Canon_MF3010-12")]).map(\.title), ["Билет.pdf"])
        XCTAssertEqual(t.update(with: []).map(\.jobID), ["Canon_MF3010-12"])
        XCTAssertTrue(t.watched.isEmpty)
        XCTAssertEqual(t.update(with: []), [], "второй раз не уведомляем")
    }

    func testQuickJobAndOrdering() {
        var t = JobCompletionTracker()
        t.watch("Canon_MF3010-10", title: "b")
        t.watch("Canon_MF3010-9", title: "a")
        t.watch("?", title: "неизвестный ID")
        XCTAssertEqual(t.update(with: []).map(\.title), ["a", "b"], "сортировка по номеру, а не по строке")
    }

    func testCancelledAreForgotten() {
        var t = JobCompletionTracker()
        t.watch("Canon_MF3010-1", title: "a")
        t.watch("Canon_MF3010-2", title: "b")
        t.watch("Other-3", title: "c")
        t.forget("Canon_MF3010-1")
        t.forgetAll(printer: "Canon_MF3010")
        XCTAssertEqual(t.update(with: []).map(\.title), ["c"])
    }
}

final class ScanOptionsTests: XCTestCase {
    func testDPI() {
        XCTAssertEqual(ScanOptions.nearestSupported(300, supported: [75, 150, 300, 600]), 300)
        XCTAssertEqual(ScanOptions.nearestSupported(250, supported: [100, 200, 400, 600]), 200)
        XCTAssertEqual(ScanOptions.nearestSupported(300, supported: [200, 400]), 400, "при равенстве — выше")
        XCTAssertEqual(ScanOptions.nearestSupported(300, supported: []), 300)
        XCTAssertEqual(ScanOptions.offeredDPI(supported: [75, 100, 150, 300, 600, 1200]), [75, 150, 300, 600, 1200])
        XCTAssertEqual(ScanOptions.offeredDPI(supported: [100, 400]), [100, 400])
        XCTAssertEqual(ScanOptions.offeredDPI(supported: []), ScanOptions.commonDPI)
        XCTAssertEqual(ScanOptions(dpi: 300).a4Pixels().width, 2480)
        XCTAssertEqual(ScanOptions(dpi: 300).a4Pixels().height, 3508)
    }

    func testNames() {
        let date = Date(timeIntervalSince1970: 1_794_571_533) // 2026-11-13 12:05:33 UTC
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ScanOptions.baseName(for: date, timeZone: utc), "Скан 2026-11-13 12-05-33")
        XCTAssertEqual(ScanOptions.baseName(for: date, timeZone: TimeZone(identifier: "Europe/Minsk")!), "Скан 2026-11-13 15-05-33")
        XCTAssertEqual(ScanOptions.uniqueName(base: "Скан", ext: "pdf", existing: []), "Скан.pdf")
        XCTAssertEqual(ScanOptions.uniqueName(base: "Скан", ext: "pdf", existing: ["Скан.pdf", "Скан (2).pdf"]), "Скан (3).pdf")
        XCTAssertEqual(ScanOptions.Format.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ScanOptions.Format.pdf.uti, "com.adobe.pdf")
    }
}

final class SettingsCodingTests: XCTestCase {
    func testDefaultsForMissingKeys() throws {
        let s = try JSONDecoder().decode(PrintSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(s, PrintSettings())
        var full = PrintSettings()
        full.booklet = true
        full.mediaSize = "A5"
        full.quality = .draft
        let back = try JSONDecoder().decode(PrintSettings.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
    }

    func testBuiltInPresetResetsBooklet() {
        var s = PrintSettings()
        s.booklet = true
        XCTAssertFalse(PrintPreset.normal.apply(to: s).booklet)
    }
}
