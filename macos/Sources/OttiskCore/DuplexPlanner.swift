import Foundation

/// Ячейка на стороне листа: страница документа (с 1) или пустое место.
public enum PageSlot: Equatable, Hashable, Sendable {
    case page(Int)
    case blank
}

/// План ручной двусторонней печати.
///
/// У MF3010 нет дуплекса, поэтому:
/// 1. печатаем лицевые стороны (1, 3, 5 … или группы по N при «N на листе»);
/// 2. человек кладёт пачку обратно в лоток;
/// 3. печатаем оборотные стороны в нужном порядке.
///
/// Каждая сторона дополняется пустыми ячейками до N, чтобы группировка
/// `number-up` не «съезжала». Если лицевых сторон больше, чем оборотных,
/// для последнего листа добавляется пустая оборотная сторона, иначе при
/// обратном порядке всё сместится на лист.
public struct DuplexPlan: Equatable, Sendable {
    public var fronts: [PageSlot]
    public var backs: [PageSlot]
    public var sheetCount: Int

    public var needsSecondPass: Bool { backs.contains { if case .page = $0 { return true } else { return false } } }
}

public enum DuplexPlanner {
    /// - Parameters:
    ///   - pages: выбранные страницы по порядку (например, результат `PageRange.parse`).
    ///   - pagesPerSheet: N для «N страниц на стороне листа».
    ///   - reverseBacks: печатать оборотные стороны с последнего листа к первому.
    ///     Для принтеров, которые выкладывают листы лицом вниз и берут бумагу сверху
    ///     пачки (как MF3010), это нужно, чтобы не перекладывать листы руками.
    public static func plan(pages: [Int], pagesPerSheet: Int = 1, reverseBacks: Bool = true) -> DuplexPlan {
        let n = max(pagesPerSheet, 1)
        guard !pages.isEmpty else { return DuplexPlan(fronts: [], backs: [], sheetCount: 0) }

        // Стороны листов по N страниц.
        var sides: [[PageSlot]] = stride(from: 0, to: pages.count, by: n).map { start in
            var side = pages[start..<min(start + n, pages.count)].map { PageSlot.page($0) }
            while side.count < n { side.append(.blank) }
            return side
        }
        if sides.count == 1 {
            return DuplexPlan(fronts: sides[0], backs: [], sheetCount: 1)
        }
        if sides.count % 2 == 1 {
            sides.append(Array(repeating: .blank, count: n))
        }
        var frontSides: [[PageSlot]] = []
        var backSides: [[PageSlot]] = []
        for (i, side) in sides.enumerated() {
            if i % 2 == 0 { frontSides.append(side) } else { backSides.append(side) }
        }
        if reverseBacks { backSides.reverse() }
        return DuplexPlan(fronts: frontSides.flatMap { $0 },
                          backs: backSides.flatMap { $0 },
                          sheetCount: frontSides.count)
    }
}

extension DuplexPlanner {
    /// План для нескольких копий: каждая копия начинается с нового листа,
    /// оборотные стороны всех копий идут одной пачкой в обратном порядке.
    public static func plan(pages: [Int], pagesPerSheet: Int = 1, reverseBacks: Bool = true, copies: Int) -> DuplexPlan {
        let count = max(copies, 1)
        let single = plan(pages: pages, pagesPerSheet: pagesPerSheet, reverseBacks: reverseBacks)
        guard count > 1, single.sheetCount > 0 else { return single }
        let n = max(pagesPerSheet, 1)
        // Одиночный лист: у копии нет оборота — всё равно нужен пустой оборот,
        // чтобы следующие копии не сдвинулись (кроме случая, когда оборотов нет вовсе).
        guard single.needsSecondPass else {
            return DuplexPlan(fronts: Array([[PageSlot]](repeating: single.fronts, count: count).joined()),
                              backs: [], sheetCount: single.sheetCount * count)
        }
        var backs = single.backs
        if backs.isEmpty { backs = Array(repeating: .blank, count: n) }
        let fronts = Array([[PageSlot]](repeating: single.fronts, count: count).joined())
        // Обороты одинаковые для каждой копии; при обратном порядке пачка
        // всё равно идёт с последнего листа последней копии — порядок копий симметричен.
        let allBacks = Array([[PageSlot]](repeating: backs, count: count).joined())
        return DuplexPlan(fronts: fronts, backs: allBacks, sheetCount: single.sheetCount * count)
    }
}

// MARK: v0.4 — проходы по готовым сторонам листов

extension DuplexPlanner {
    /// Ручная двусторонняя по уже собранному PDF: стороны 1…S (раскладка «N на листе»,
    /// поля и надписи уже внутри). Проход 1 — нечётные стороны (1, 3, 5…),
    /// проход 2 — чётные; при нечётном S в проход 2 добавляется пустая сторона для последнего листа.
    public static func sidesPlan(sideCount: Int, reverseBacks: Bool = true, copies: Int = 1) -> DuplexPlan {
        guard sideCount > 0 else { return DuplexPlan(fronts: [], backs: [], sheetCount: 0) }
        return plan(pages: Array(1...sideCount), pagesPerSheet: 1, reverseBacks: reverseBacks, copies: copies)
    }

    /// Брошюра: собранный PDF идёт «лицо, оборот, лицо, оборот…» (стороны 1…2K).
    public static func bookletPasses(sideCount: Int, reverseBacks: Bool = true, copies: Int = 1) -> DuplexPlan {
        let sheets = sideCount / 2
        guard sheets > 0 else { return DuplexPlan(fronts: [], backs: [], sheetCount: 0) }
        let fronts = (0..<sheets).map { PageSlot.page(2 * $0 + 1) }
        var backs = (0..<sheets).map { PageSlot.page(2 * $0 + 2) }
        if reverseBacks { backs.reverse() }
        let n = max(copies, 1)
        return DuplexPlan(fronts: Array([[PageSlot]](repeating: fronts, count: n).joined()),
                          backs: Array([[PageSlot]](repeating: backs, count: n).joined()),
                          sheetCount: sheets * n)
    }
}

/// Когда можно печатать вторую сторону: только после того, как первое задание ушло из очереди CUPS.
///
/// Важно: «ушло из CUPS» значит, что данные переданы принтеру. У MF3010 последние
/// листы могут ещё выезжать пару секунд — поэтому в окне есть напоминание дождаться последнего листа.
public struct DuplexGate: Equatable, Sendable {
    public let frontJobID: String
    /// Очередь хотя бы раз прочитана после отправки первой стороны.
    public private(set) var checkedQueue = false
    public private(set) var frontFinished = false

    public init(frontJobID: String) {
        self.frontJobID = frontJobID
    }

    /// Вызывается после каждого чтения очереди (`lpstat -o`), начиная с момента отправки.
    public mutating func update(queue: [PrintJob]) {
        checkedQueue = true
        if !queue.contains(where: { $0.id == frontJobID }) { frontFinished = true }
    }

    /// Трекер увидел, что задание завершилось.
    public mutating func markFinished() {
        checkedQueue = true
        frontFinished = true
    }

    public var canPrintBacks: Bool { checkedQueue && frontFinished }
}
