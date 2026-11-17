import XCTest
@testable import OttiskCore

final class PendingDuplexTests: XCTestCase {
    private func sample(createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> PendingDuplex {
        var s = PrintSettings()
        s.copies = 1
        s.pagesPerSheet = 2
        s.tonerSave = true
        return PendingDuplex(documentName: "Отчёт.pdf", printer: "Canon_MF3010", backsFileName: "backs-ab12cd34.pdf",
                             sheetCount: 5, frontJobID: "Canon_MF3010-42", historyID: UUID(), settings: s,
                             driver: ResolvedDriverOptions(tonerSave: (key: "CNTonerSaving", value: "True"),
                                                           draft: [(key: "Resolution", value: "300")]),
                             createdAt: createdAt)
    }

    func testRoundTripKeepsEverything() throws {
        let p = sample()
        let back = try PendingDuplex.decode(try p.encode())
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.driver.resolved, p.driver.resolved)
        XCTAssertEqual(back.driver.resolved.tonerSave?.key, "CNTonerSaving")
        XCTAssertEqual(back.driver.resolved.draft.first?.value, "300")
        XCTAssertEqual(back.settings.pagesPerSheet, 2)
    }

    func testBrokenJSONThrows() {
        XCTAssertThrowsError(try PendingDuplex.decode(Data("{\"documentName\": 1}".utf8)))
    }

    func testDecisions() {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let p = sample(createdAt: created)
        let hour = created.addingTimeInterval(3600)
        XCTAssertEqual(PendingDuplexPolicy.decide(p, now: hour, backsFileExists: true, availablePrinters: ["Canon_MF3010"]), .offer)
        XCTAssertEqual(PendingDuplexPolicy.decide(p, now: hour, backsFileExists: true, availablePrinters: nil), .offer)
        XCTAssertEqual(PendingDuplexPolicy.decide(p, now: hour, backsFileExists: true, availablePrinters: ["Other"]), .offerPrinterMissing)
        XCTAssertEqual(PendingDuplexPolicy.decide(p, now: hour, backsFileExists: false, availablePrinters: ["Canon_MF3010"]), .discardMissingFile)
        let week = created.addingTimeInterval(PendingDuplexPolicy.defaultMaxAge + 1)
        XCTAssertEqual(PendingDuplexPolicy.decide(p, now: week, backsFileExists: true, availablePrinters: ["Canon_MF3010"]), .discardExpired)
        let past = created.addingTimeInterval(-86_400)
        XCTAssertEqual(PendingDuplexPolicy.decide(p, now: past, backsFileExists: true, availablePrinters: ["Canon_MF3010"]), .offer,
                       "если часы ушли назад, задание не выбрасываем")
    }

    func testWhenText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Minsk")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 16, minute: 30))!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 14, minute: 5))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 30))!
        let older = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18, minute: 40))!
        XCTAssertEqual(PendingDuplexPolicy.whenText(today, now: now, calendar: cal), "сегодня в 14:05")
        XCTAssertEqual(PendingDuplexPolicy.whenText(yesterday, now: now, calendar: cal), "вчера в 09:30")
        XCTAssertEqual(PendingDuplexPolicy.whenText(older, now: now, calendar: cal), "10.11 в 18:40")
    }
}
