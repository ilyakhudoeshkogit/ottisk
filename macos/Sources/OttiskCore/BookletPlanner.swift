import Foundation

/// Одна сторона листа брошюры: две страницы рядом (левая и правая половина альбомного листа).
public struct BookletSide: Equatable, Sendable {
    public var left: PageSlot
    public var right: PageSlot

    public init(left: PageSlot, right: PageSlot) {
        self.left = left
        self.right = right
    }
}

/// Лист брошюры: лицевая и оборотная стороны.
public struct BookletSheet: Equatable, Sendable {
    public var front: BookletSide
    public var back: BookletSide
}

/// План брошюры для принтера без дуплекса: что печатать в первом и втором проходе.
public struct BookletPlan: Equatable, Sendable {
    public var sheets: [BookletSheet]
    /// Лицевые стороны по порядку печати.
    public var fronts: [BookletSide]
    /// Оборотные стороны по порядку печати (с учётом `reverseBacks`).
    public var backs: [BookletSide]

    public var sheetCount: Int { sheets.count }
}

/// Раскладка страниц «для сгиба»: печатаем, складываем пачку пополам, получаем книжечку.
///
/// Для 8 страниц: лист 1 — лицо [8 | 1], оборот [2 | 7]; лист 2 — лицо [6 | 3], оборот [4 | 5].
/// Число страниц дополняется пустыми до кратного 4 (в конце брошюры).
public enum BookletPlanner {
    public static func paddedCount(_ pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return Int((Double(pageCount) / 4).rounded(.up)) * 4
    }

    public static func sheetCount(pageCount: Int) -> Int {
        paddedCount(pageCount) / 4
    }

    /// - Parameters:
    ///   - pages: выбранные страницы документа по порядку (номера с 1).
    ///   - reverseBacks: печатать обороты с последнего листа (для MF3010 — да, см. DuplexPlanner).
    public static func plan(pages: [Int], reverseBacks: Bool = true) -> BookletPlan {
        let total = paddedCount(pages.count)
        guard total > 0 else { return BookletPlan(sheets: [], fronts: [], backs: []) }
        func slot(_ position: Int) -> PageSlot {
            // position — номер страницы в брошюре с 1.
            position <= pages.count ? .page(pages[position - 1]) : .blank
        }
        var sheets: [BookletSheet] = []
        for i in 0..<(total / 4) {
            let front = BookletSide(left: slot(total - 2 * i), right: slot(2 * i + 1))
            let back = BookletSide(left: slot(2 * i + 2), right: slot(total - 2 * i - 1))
            sheets.append(BookletSheet(front: front, back: back))
        }
        let fronts = sheets.map(\.front)
        var backs = sheets.map(\.back)
        if reverseBacks { backs.reverse() }
        return BookletPlan(sheets: sheets, fronts: fronts, backs: backs)
    }
}
