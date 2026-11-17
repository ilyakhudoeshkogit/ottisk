import XCTest
@testable import OttiskCore

final class PageRangeTests: XCTestCase {
    func testParse() throws {
        XCTAssertEqual(try PageRange.parse("", pageCount: 3), [1, 2, 3])
        XCTAssertEqual(try PageRange.parse("1-3, 5", pageCount: 10), [1, 2, 3, 5])
        XCTAssertEqual(try PageRange.parse("8-", pageCount: 10), [8, 9, 10])
        XCTAssertEqual(try PageRange.parse("-2", pageCount: 10), [1, 2])
        XCTAssertEqual(try PageRange.parse("3–4; 4, 1", pageCount: 10), [1, 3, 4])
        XCTAssertEqual(try PageRange.parse(" 2 - 3 ", pageCount: 10), [2, 3])
    }

    func testErrors() {
        XCTAssertThrowsError(try PageRange.parse("abc", pageCount: 3)) { XCTAssertEqual($0 as? PageRange.ParseError, .invalidToken("abc")) }
        XCTAssertThrowsError(try PageRange.parse("5", pageCount: 3)) { XCTAssertEqual($0 as? PageRange.ParseError, .outOfBounds(5, max: 3)) }
        XCTAssertThrowsError(try PageRange.parse("3-1", pageCount: 3)) { XCTAssertEqual($0 as? PageRange.ParseError, .reversed("3-1")) }
        XCTAssertThrowsError(try PageRange.parse("0", pageCount: 3))
        XCTAssertThrowsError(try PageRange.parse("1-2-3", pageCount: 3))
        XCTAssertThrowsError(try PageRange.parse(",", pageCount: 3))
    }

    func testCupsString() {
        XCTAssertEqual(PageRange.cupsString([1, 2, 3, 5, 7, 8]), "1-3,5,7-8")
        XCTAssertEqual(PageRange.cupsString([4]), "4")
        XCTAssertEqual(PageRange.cupsString([]), "")
        XCTAssertTrue(PageRange.isAll([1, 2, 3], pageCount: 3))
        XCTAssertFalse(PageRange.isAll([1, 3], pageCount: 3))
    }
}

final class LPArgumentsTests: XCTestCase {
    func testDefault() {
        let args = LPArgumentsBuilder.arguments(printer: "Canon_MF3010", settings: PrintSettings(),
                                                title: "Отчёт.pdf", pages: nil, files: ["/tmp/a.pdf"])
        XCTAssertEqual(args, ["-d", "Canon_MF3010", "-t", "Отчёт.pdf", "-o", "fit-to-page", "--", "/tmp/a.pdf"])
    }

    func testFull() {
        var s = PrintSettings()
        s.copies = 3
        s.collate = false
        s.pagesPerSheet = 4
        s.orientation = .landscape
        s.fitToPage = false
        s.mediaSize = "A4"
        s.quality = .draft
        s.tonerSave = true
        s.reverseOrder = true
        let driver = ResolvedDriverOptions(tonerSave: ("CNTonerSaving", "True"), draft: [("Resolution", "300dpi")])
        let args = LPArgumentsBuilder.arguments(printer: "P", settings: s, driver: driver, title: nil,
                                                pages: [1, 2, 3, 9], files: ["/x y.pdf"])
        XCTAssertEqual(args, ["-d", "P", "-n", "3", "-o", "collate=false", "-P", "1-3,9",
                              "-o", "number-up=4", "-o", "number-up-layout=lrtb",
                              "-o", "orientation-requested=4", "-o", "media=A4",
                              "-o", "print-quality=3", "-o", "Resolution=300dpi",
                              "-o", "CNTonerSaving=True", "-o", "outputorder=reverse",
                              "--", "/x y.pdf"])
        XCTAssertTrue(LPArgumentsBuilder.shellPreview(args).hasSuffix("-- '/x y.pdf'"))
    }

    func testTonerSaveWithoutDriverOptionIsIgnored() {
        var s = PrintSettings()
        s.tonerSave = true
        let args = LPArgumentsBuilder.arguments(printer: "P", settings: s, title: nil, pages: nil, files: ["f"])
        XCTAssertFalse(args.contains { $0.contains("Toner") })
    }
}

final class PresetTests: XCTestCase {
    func testApplyKeepsCopiesAndRange() {
        var base = PrintSettings()
        base.copies = 2
        base.pageRange = "1-4"
        base.mediaSize = "A4"
        let d = PrintPreset.draft.apply(to: base)
        XCTAssertEqual(d.copies, 2)
        XCTAssertEqual(d.pageRange, "1-4")
        XCTAssertEqual(d.mediaSize, "A4")
        XCTAssertEqual(d.quality, .draft)
        XCTAssertEqual(d.pagesPerSheet, 2)
        XCTAssertEqual(PrintPreset.matching(d), .draft)
        XCTAssertEqual(PrintPreset.matching(PrintPreset.manualDuplex.apply(to: base)), .manualDuplex)
        var custom = base
        custom.pagesPerSheet = 9
        XCTAssertNil(PrintPreset.matching(custom))
    }

    func testDriverMatcher() {
        let canonLike = [
            PrinterOption(key: "PageSize", label: "Media Size", choices: ["A4", "Letter"], defaultChoice: "A4"),
            PrinterOption(key: "CNTonerSaving", label: "Toner Save", choices: ["False", "True"], defaultChoice: "False"),
            PrinterOption(key: "Resolution", label: "Resolution", choices: ["600dpi", "300dpi"], defaultChoice: "600dpi"),
        ]
        let r = DriverOptionMatcher.resolve(canonLike)
        XCTAssertEqual(r.tonerSave?.key, "CNTonerSaving")
        XCTAssertEqual(r.tonerSave?.value, "True")
        XCTAssertEqual(r.draft.first?.value, "300dpi")
        XCTAssertEqual(DriverOptionMatcher.mediaOption(in: canonLike)?.key, "PageSize")

        let hpLike = [PrinterOption(key: "EconoMode", label: "EconoMode", choices: ["PrinterDefault", "False", "True"], defaultChoice: "PrinterDefault")]
        XCTAssertEqual(DriverOptionMatcher.tonerSave(in: hpLike)?.value, "True")

        let level = [PrinterOption(key: "TonerSaveMode", label: "Toner Save Mode", choices: ["Off", "Level1", "Level2"], defaultChoice: "Off")]
        XCTAssertEqual(DriverOptionMatcher.tonerSave(in: level)?.value, "Level1")

        XCTAssertNil(DriverOptionMatcher.tonerSave(in: [PrinterOption(key: "Duplex", label: "Duplex", choices: ["None"], defaultChoice: "None")]))
    }
}

final class DuplexPlannerTests: XCTestCase {
    func testEvenPages() {
        let p = DuplexPlanner.plan(pages: [1, 2, 3, 4, 5, 6], reverseBacks: true)
        XCTAssertEqual(p.fronts, [.page(1), .page(3), .page(5)])
        XCTAssertEqual(p.backs, [.page(6), .page(4), .page(2)])
        XCTAssertEqual(p.sheetCount, 3)
        XCTAssertTrue(p.needsSecondPass)
    }

    func testOddPagesAddsBlankFirstWhenReversed() {
        let p = DuplexPlanner.plan(pages: [1, 2, 3, 4, 5], reverseBacks: true)
        XCTAssertEqual(p.fronts, [.page(1), .page(3), .page(5)])
        XCTAssertEqual(p.backs, [.blank, .page(4), .page(2)])
    }

    func testNotReversed() {
        let p = DuplexPlanner.plan(pages: [1, 2, 3], reverseBacks: false)
        XCTAssertEqual(p.fronts, [.page(1), .page(3)])
        XCTAssertEqual(p.backs, [.page(2), .blank])
    }

    func testSinglePage() {
        let p = DuplexPlanner.plan(pages: [7])
        XCTAssertEqual(p.fronts, [.page(7)])
        XCTAssertEqual(p.backs, [])
        XCTAssertFalse(p.needsSecondPass)
    }

    func testTwoUpPadsSides() {
        // 5 страниц, 2 на стороне: стороны [1,2] [3,4] [5,_] → лист1: [1,2]/[3,4], лист2: [5,_]/[_,_]
        let p = DuplexPlanner.plan(pages: [1, 2, 3, 4, 5], pagesPerSheet: 2, reverseBacks: true)
        XCTAssertEqual(p.fronts, [.page(1), .page(2), .page(5), .blank])
        XCTAssertEqual(p.backs, [.blank, .blank, .page(3), .page(4)])
        XCTAssertEqual(p.sheetCount, 2)
    }

    func testSelectedRange() {
        let p = DuplexPlanner.plan(pages: [2, 3, 4, 5])
        XCTAssertEqual(p.fronts, [.page(2), .page(4)])
        XCTAssertEqual(p.backs, [.page(5), .page(3)])
    }

    func testEmpty() {
        XCTAssertEqual(DuplexPlanner.plan(pages: []).sheetCount, 0)
    }
}

final class HistoryTests: XCTestCase {
    func testAppendLimitAndRoundTrip() throws {
        var entries: [HistoryEntry] = []
        for i in 0..<5 {
            entries = HistoryLog.appending(HistoryEntry(fileName: "f\(i).pdf", filePath: "/tmp/f\(i).pdf", printer: "P",
                                                        pageCount: 2, copies: 2, presetTitle: "Обычно", jobIDs: ["P-\(i)"]),
                                           to: entries, limit: 3)
        }
        XCTAssertEqual(entries.map(\.fileName), ["f4.pdf", "f3.pdf", "f2.pdf"])
        XCTAssertEqual(HistoryLog.totalPages(entries), 12)
        let data = try HistoryLog.encode(entries)
        let back = try HistoryLog.decode(data)
        XCTAssertEqual(back.map(\.id), entries.map(\.id))
    }

    func testKinds() {
        XCTAssertEqual(DocumentKind.from(pathExtension: "PDF"), .pdf)
        XCTAssertEqual(DocumentKind.from(pathExtension: "heic"), .image)
        XCTAssertEqual(DocumentKind.from(pathExtension: "docx"), .richText)
        XCTAssertEqual(DocumentKind.from(pathExtension: "txt"), .plainText)
        XCTAssertEqual(DocumentKind.from(pathExtension: "pages"), .unsupported)
    }

    func testSheetCount() {
        var s = PrintSettings()
        XCTAssertEqual(s.sheetCount(selectedPages: 5), 5)
        s.pagesPerSheet = 2
        XCTAssertEqual(s.sheetCount(selectedPages: 5), 3)
        s.manualDuplex = true
        XCTAssertEqual(s.sheetCount(selectedPages: 5), 2)
    }
}

final class DuplexCopiesTests: XCTestCase {
    func testTwoCopiesOddPages() {
        let p = DuplexPlanner.plan(pages: [1, 2, 3], reverseBacks: true, copies: 2)
        // Копия: лицо [1,3], оборот (обратно) [_,2]. Две копии подряд.
        XCTAssertEqual(p.fronts, [.page(1), .page(3), .page(1), .page(3)])
        XCTAssertEqual(p.backs, [.blank, .page(2), .blank, .page(2)])
        XCTAssertEqual(p.sheetCount, 4)
    }

    func testCopiesNotReversed() {
        let p = DuplexPlanner.plan(pages: [1, 2, 3, 4], reverseBacks: false, copies: 2)
        XCTAssertEqual(p.fronts, [.page(1), .page(3), .page(1), .page(3)])
        XCTAssertEqual(p.backs, [.page(2), .page(4), .page(2), .page(4)])
    }

    func testCopiesSinglePage() {
        let p = DuplexPlanner.plan(pages: [1], copies: 3)
        XCTAssertEqual(p.fronts, [.page(1), .page(1), .page(1)])
        XCTAssertFalse(p.needsSecondPass)
    }
}
