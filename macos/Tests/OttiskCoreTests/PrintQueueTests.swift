import XCTest
@testable import OttiskCore

private func make(_ pages: [Int]) -> PrintQueue {
    var q = PrintQueue()
    q.sync(with: pages.enumerated().map { QueueDocumentInfo(id: UUID(), name: "d\($0.offset + 1)", pageCount: $0.element) })
    return q
}

final class PrintQueueTests: XCTestCase {
    func testSyncKeepsOverridesAndOrder() {
        var q = make([3, 5])
        let first = q.items[0].id
        q.update(first) { $0.hasOverride = true; $0.copies = 3 }
        let extra = QueueDocumentInfo(id: UUID(), name: "новый", pageCount: 1)
        q.sync(with: [QueueDocumentInfo(id: q.items[1].id, name: "d2", pageCount: 5),
                      QueueDocumentInfo(id: first, name: "d1", pageCount: 3), extra])
        XCTAssertEqual(q.items.map(\.name), ["d2", "d1", "новый"])
        XCTAssertEqual(q.item(first)?.copies, 3)
        XCTAssertTrue(q.item(first)!.hasOverride)
    }

    func testMove() {
        var q = make([1, 1, 1, 1])
        let names = q.items.map(\.name)
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)   // d1 после d3
        XCTAssertEqual(q.items.map(\.name), [names[1], names[2], names[0], names[3]])
        q.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(q.items.map(\.name), [names[3], names[1], names[2], names[0]])
    }

    func testRemove() {
        var q = make([1, 2])
        q.remove(q.items[0].id)
        XCTAssertEqual(q.items.map(\.name), ["d2"])
    }

    func testEffectiveSettings() {
        var q = make([10])
        var shared = PrintSettings()
        shared.copies = 2
        shared.pageRange = "1"
        shared.pagesPerSheet = 2
        let id = q.items[0].id
        // Как общий пресет: копии пресета, диапазон одиночного документа не переносится.
        var s = q.items[0].effectiveSettings(shared: shared)
        XCTAssertEqual(s.copies, 2); XCTAssertEqual(s.pageRange, ""); XCTAssertEqual(s.pagesPerSheet, 2)
        q.update(id) { $0.hasOverride = true; $0.copies = 5; $0.pageRange = "2-4" }
        s = q.items[0].effectiveSettings(shared: shared)
        XCTAssertEqual(s.copies, 5); XCTAssertEqual(s.pageRange, "2-4"); XCTAssertEqual(s.pagesPerSheet, 2)
        XCTAssertEqual(try q.items[0].pages(), [2, 3, 4])
    }

    func testInvalidRangeIsSkipped() {
        var q = make([3, 3])
        let bad = q.items[0].id
        q.update(bad) { $0.hasOverride = true; $0.pageRange = "9" }
        XCTAssertNotNil(q.items[0].rangeError)
        q.start()
        XCTAssertEqual(q.item(bad)?.state, .skipped)
        XCTAssertEqual(q.printable.count, 1)
        XCTAssertTrue(q.isRunning)
    }

    func testStartWithNothingPrintable() {
        var q = PrintQueue()
        XCTAssertFalse(q.canStart)
        q.start()
        XCTAssertFalse(q.isRunning)
        XCTAssertEqual(q.nextStep(), .finished)
    }

    func testSequentialRun() {
        var q = make([1, 1, 1])
        let ids = q.items.map(\.id)
        q.start()
        for id in ids {
            XCTAssertEqual(q.nextStep(), .print(id))
            q.markPrinting(id)
            q.markDone(id)
        }
        XCTAssertEqual(q.nextStep(), .finished)
        q.finish()
        XCTAssertFalse(q.isRunning)
        XCTAssertEqual(q.doneCount, 3)
    }

    func testWaitsForFlipBeforeNext() {
        var q = make([2, 2])
        let (a, b) = (q.items[0].id, q.items[1].id)
        q.start()
        XCTAssertEqual(q.nextStep(), .print(a))
        q.markPrinting(a)
        q.markAwaitingFlip(a)
        XCTAssertEqual(q.nextStep(), .waitForFlip(a))   // b не стартует, пока не нажали «перевернул»
        XCTAssertEqual(q.nextStep(), .waitForFlip(a))
        q.markDone(a)
        XCTAssertEqual(q.nextStep(), .print(b))
    }

    func testFailureDoesNotStopOthers() {
        var q = make([1, 1])
        let (a, b) = (q.items[0].id, q.items[1].id)
        q.start()
        q.markFailed(a, "нет файла")
        XCTAssertEqual(q.nextStep(), .print(b))
        q.markDone(b)
        XCTAssertEqual(q.failedCount, 1)
        XCTAssertEqual(q.doneCount, 1)
        XCTAssertEqual(q.nextStep(), .finished)
    }

    func testStopSkipsRemaining() {
        var q = make([1, 1, 1])
        let ids = q.items.map(\.id)
        q.start()
        q.markDone(ids[0])
        q.stop()
        XCTAssertEqual(q.skippedCount, 2)
        XCTAssertEqual(q.nextStep(), .finished)
    }

    func testRunLocksReorder() {
        var q = make([1, 1])
        let first = q.items[0].id
        q.start()
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        q.remove(first)
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.items[0].id, first)
    }

    func testRestartResetsStates() {
        var q = make([1, 1])
        q.start()
        for item in q.items { q.markDone(item.id) }
        q.finish()
        XCTAssertTrue(q.canStart)   // повторный запуск разрешён
        q.start()
        XCTAssertEqual(q.printable.count, 2)
    }

    func testMergedPagesRangesAndCopies() {
        var q = make([3, 4, 2])
        q.update(q.items[0].id) { $0.hasOverride = true; $0.pageRange = "2-3"; $0.copies = 2 }
        q.update(q.items[1].id) { $0.hasOverride = true; $0.pageRange = "1,4" }
        q.start()
        let a = q.items[0].id, b = q.items[1].id, c = q.items[2].id
        let pages = q.mergedPages()
        XCTAssertEqual(pages, [
            MergedPage(itemID: a, page: 2), MergedPage(itemID: a, page: 3),
            MergedPage(itemID: a, page: 2), MergedPage(itemID: a, page: 3),
            MergedPage(itemID: b, page: 1), MergedPage(itemID: b, page: 4),
            MergedPage(itemID: c, page: 1), MergedPage(itemID: c, page: 2),
        ])
    }

    func testMergedSkipsInvalidAndFinished() {
        var q = make([2, 2, 2])
        q.update(q.items[0].id) { $0.hasOverride = true; $0.pageRange = "7" }
        q.start()
        q.markDone(q.items[1].id)
        XCTAssertEqual(q.mergedPages().map(\.itemID), [q.items[2].id, q.items[2].id])
    }

    func testMergedSettingsClearRange() {
        var s = PrintSettings()
        s.pageRange = "3"; s.manualDuplex = true; s.copies = 2
        let m = PrintQueue.mergedSettings(shared: s)
        XCTAssertEqual(m.pageRange, "")
        XCTAssertTrue(m.manualDuplex)
        XCTAssertEqual(m.copies, 2)
    }
}
