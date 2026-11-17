import Foundation

/// Последовательность «логических» страниц до раскладки по листам.
public enum LogicalPages {
    /// Выбранные страницы → чётные/нечётные → повтор каждой → пустые разделители.
    public static func sequence(selected: [Int], parity: PageParity = .all,
                                repeatEach: Int = 1, blankEvery: Int = 0) -> [PageSlot] {
        let filtered: [Int]
        switch parity {
        case .all: filtered = selected
        case .odd: filtered = selected.filter { $0 % 2 == 1 }
        case .even: filtered = selected.filter { $0 % 2 == 0 }
        }
        let times = min(max(repeatEach, 1), 16)
        var result: [PageSlot] = []
        var sinceBlank = 0
        for page in filtered {
            for _ in 0..<times { result.append(.page(page)) }
            sinceBlank += 1
            if blankEvery > 0, sinceBlank == blankEvery, page != filtered.last {
                result.append(.blank)
                sinceBlank = 0
            }
        }
        return result
    }

    public static func sequence(selected: [Int], settings: PrintSettings) -> [PageSlot] {
        sequence(selected: selected, parity: settings.parity, repeatEach: settings.repeatEach,
                 blankEvery: settings.blankEvery)
    }
}

// MARK: Результат раскладки

public enum LabelAlignment: String, Equatable, Hashable, Sendable {
    case left, center, right
}

/// Надпись на листе. `y` — середина строки.
public struct SideLabel: Equatable, Hashable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var alignment: LabelAlignment
    public var fontSize: Double
    public var monospaced: Bool

    public init(text: String, x: Double, y: Double, alignment: LabelAlignment, fontSize: Double, monospaced: Bool = false) {
        self.text = text
        self.x = x
        self.y = y
        self.alignment = alignment
        self.fontSize = fontSize
        self.monospaced = monospaced
    }
}

public struct LayoutLine: Equatable, Hashable, Sendable {
    public var x1: Double, y1: Double, x2: Double, y2: Double
    /// Толщина в пунктах.
    public var width: Double
    public var dashed: Bool

    public init(x1: Double, y1: Double, x2: Double, y2: Double, width: Double, dashed: Bool = false) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        self.width = width
        self.dashed = dashed
    }
}

/// Одна страница документа на листе.
public struct SidePlacement: Equatable, Hashable, Sendable {
    public var slot: PageSlot
    /// Ячейка (для рамки и обрезки).
    public var cell: LayoutRect
    /// Какой кусок исходной страницы берём (в координатах страницы, с учётом поворота).
    public var crop: LayoutRect
    /// Куда этот кусок ложится на листе (уже с масштабом).
    public var target: LayoutRect
    public var scale: Double
}

/// Одна сторона листа.
public struct SideLayout: Equatable, Hashable, Sendable {
    public var size: LayoutSize
    /// Поле для содержимого (внутри полей) — его показывает превью пунктиром.
    public var area: LayoutRect
    public var placements: [SidePlacement]
    public var lines: [LayoutLine]
    public var labels: [SideLabel]
    /// Оборот (при ручной двусторонней и в брошюре).
    public var isBack: Bool
}

public struct LayoutPlan: Equatable, Sendable {
    public var sides: [SideLayout]

    /// Листов бумаги на одну копию.
    public func sheetCount(twoSided: Bool) -> Int {
        twoSided ? (sides.count + 1) / 2 : sides.count
    }
}

/// Сведения об исходном документе для раскладки.
public struct LayoutSource {
    /// Размер страницы n (с 1) с учётом её поворота.
    public var pageSize: (Int) -> LayoutSize
    /// Непустая область страницы n (для обрезки белых полей) или nil, если неизвестна.
    public var contentBox: (Int) -> LayoutRect?
    /// Для колонтитула: «имя файла · дата».
    public var headerText: String?

    public init(pageSize: @escaping (Int) -> LayoutSize,
                contentBox: @escaping (Int) -> LayoutRect? = { _ in nil },
                headerText: String? = nil) {
        self.pageSize = pageSize
        self.contentBox = contentBox
        self.headerText = headerText
    }
}

// MARK: Раскладка

/// Вся геометрия печати: что, где и в каком масштабе окажется на каждом листе.
/// Чистая логика без AppKit — её проверяют тесты, а рисует `LayoutRenderer` в приложении.
public enum LayoutPlanner {
    /// Промежуток между ячейками при «N на листе», мм.
    public static let cellGapMM = 4.0
    /// Минимальное поле вокруг половинок брошюры, мм.
    public static let bookletMinMarginMM = 4.0
    /// Рамка ЕСКД по ГОСТ 2.104 / СТП БГУИР 01-2024 п. 3.1.3: 20 мм слева, 5 мм с остальных сторон.
    public static let eskdFrameMM = PageMargins(top: 5, bottom: 5, left: 20, right: 5)
    /// Высота основной надписи формы 2а, мм.
    public static let titleBlockHeightMM = 15.0
    public static let titleBlockWidthMM = 185.0

    /// Минимальные поля текста внутри рамки: по ГОСТ Р 2.105-2019 п. 5.1.3 —
    /// не менее 3 мм от рамки до начала/конца строк и не менее 10 мм до верхней/нижней рамки.
    public static func eskdTextMargins(titleBlock: Bool) -> PageMargins {
        PageMargins(top: 5 + 10, bottom: 5 + 10 + (titleBlock ? titleBlockHeightMM : 0), left: 20 + 3, right: 5 + 3)
    }

    public static func plan(slots: [PageSlot], source: LayoutSource, settings: PrintSettings,
                            sheet baseSheet: LayoutSize = .a4) -> LayoutPlan {
        guard !slots.isEmpty else { return LayoutPlan(sides: []) }
        var sides: [SideLayout]
        if settings.booklet {
            sides = bookletSides(slots: slots, source: source, settings: settings, sheet: baseSheet.portrait)
        } else {
            sides = regularSides(slots: slots, source: source, settings: settings, sheet: baseSheet.portrait)
        }
        if settings.reverseOrder && !settings.manualDuplex && !settings.booklet {
            sides.reverse()
        }
        addOverlays(&sides, settings: settings, source: source)
        return LayoutPlan(sides: sides)
    }

    // MARK: Поля

    /// Поля стороны листа с учётом переплёта, зеркальности и рамки ЕСКД, мм.
    public static func effectiveMargins(_ settings: PrintSettings, isBack: Bool) -> PageMargins {
        var m = settings.margins.clamped
        let gutter = min(max(settings.gutter, 0), 60)
        let mirror = settings.mirrorMargins && isBack
        switch settings.gutterEdge {
        case .left:
            if mirror { swap(&m.left, &m.right) }
            if mirror { m.right += gutter } else { m.left += gutter }
        case .top:
            if mirror { swap(&m.top, &m.bottom) }
            if mirror { m.bottom += gutter } else { m.top += gutter }
        }
        if settings.eskdFrame || settings.eskdTitleBlock {
            m = m.atLeast(eskdTextMargins(titleBlock: settings.eskdTitleBlock))
        }
        if settings.fileHeader { m.top = max(m.top, 10) }
        return m
    }

    private static func area(of sheet: LayoutSize, margins m: PageMargins) -> LayoutRect {
        LayoutRect(size: sheet).inset(top: Units.pt(m.top), left: Units.pt(m.left),
                                      bottom: Units.pt(m.bottom), right: Units.pt(m.right))
    }

    // MARK: Обычные листы и «N на листе»

    static func perSheet(_ settings: PrintSettings) -> Int {
        if settings.slideNotes { return [3, 4, 6].contains(settings.pagesPerSheet) ? settings.pagesPerSheet : 4 }
        return PrintSettings.allowedPagesPerSheet.contains(settings.pagesPerSheet) ? settings.pagesPerSheet : 1
    }

    private static func regularSides(slots: [PageSlot], source: LayoutSource, settings: PrintSettings,
                                     sheet: LayoutSize) -> [SideLayout] {
        let n = perSheet(settings)
        let groups: [[PageSlot]] = stride(from: 0, to: slots.count, by: n).map { start in
            var g = Array(slots[start..<min(start + n, slots.count)])
            while g.count < n { g.append(.blank) }
            return g
        }
        // Представительная страница — первая настоящая (для выбора ориентации и сетки).
        let firstPage = slots.first { if case .page = $0 { return true } else { return false } }
        let repSize: LayoutSize = {
            if case .page(let p) = firstPage { return crop(for: p, source: source, settings: settings).sizeValue }
            return sheet
        }()
        return groups.enumerated().map { index, group in
            let isBack = settings.manualDuplex && index % 2 == 1
            let margins = effectiveMargins(settings, isBack: isBack)
            if n == 1 {
                var pageSize = repSize
                if case .page(let p) = group[0] { pageSize = crop(for: p, source: source, settings: settings).sizeValue }
                let sideSize = orient(sheet, for: pageSize, settings.orientation)
                let a = area(of: sideSize, margins: margins)
                let cell = a
                let placement = place(group[0], in: cell, source: source, settings: settings, single: true)
                return SideLayout(size: sideSize, area: a, placements: placement.map { [$0] } ?? [],
                                  lines: [], labels: [], isBack: isBack)
            }
            let grid = chooseGrid(n: n, page: repSize, sheet: sheet, margins: margins, settings: settings)
            let a = area(of: grid.sheet, margins: margins)
            let cells = gridCells(area: a, columns: grid.columns, rows: grid.rows, order: settings.nUpOrder)
            var placements: [SidePlacement] = []
            var lines: [LayoutLine] = []
            for (cell, slot) in zip(cells, group) {
                var pageCell = cell
                if settings.slideNotes {
                    pageCell = LayoutRect(x: cell.x, y: cell.y, width: cell.width * 0.55, height: cell.height)
                    lines += noteLines(in: LayoutRect(x: pageCell.maxX + Units.pt(4), y: cell.y,
                                                      width: cell.maxX - pageCell.maxX - Units.pt(4), height: cell.height))
                }
                if settings.numbering.enabled { pageCell = pageCell.inset(top: 0, left: 0, bottom: Units.pt(4.5), right: 0) }
                if let p = place(slot, in: pageCell, source: source, settings: settings, single: false) {
                    placements.append(p)
                } else {
                    placements.append(SidePlacement(slot: .blank, cell: pageCell, crop: LayoutRect(x: 0, y: 0, width: 0, height: 0),
                                                    target: pageCell, scale: 1))
                }
                if settings.cellBorders {
                    lines += rectLines(settings.slideNotes ? pageCell : cell, width: 0.5)
                }
            }
            return SideLayout(size: grid.sheet, area: a, placements: placements, lines: lines, labels: [], isBack: isBack)
        }
    }

    /// Ориентация листа для одной страницы на листе.
    public static func orient(_ sheet: LayoutSize, for page: LayoutSize, _ orientation: PageOrientation) -> LayoutSize {
        switch orientation {
        case .portrait: return sheet.portrait
        case .landscape: return sheet.landscape
        case .auto: return page.isLandscape ? sheet.landscape : sheet.portrait
        }
    }

    public struct Grid: Equatable, Sendable {
        public var columns: Int
        public var rows: Int
        public var sheet: LayoutSize
    }

    /// Сетка и ориентация листа, при которых страница выходит крупнее всего.
    public static func chooseGrid(n: Int, page: LayoutSize, sheet: LayoutSize, margins: PageMargins,
                                  settings: PrintSettings) -> Grid {
        if settings.slideNotes {
            return Grid(columns: 1, rows: n, sheet: sheet.portrait)
        }
        var pairs: [(Int, Int)] = []
        for c in 1...n where n % c == 0 { pairs.append((c, n / c)) }
        let sheets: [LayoutSize]
        switch settings.orientation {
        case .portrait: sheets = [sheet.portrait]
        case .landscape: sheets = [sheet.landscape]
        case .auto: sheets = [sheet.portrait, sheet.landscape]
        }
        var best: (Grid, Double)?
        let gap = Units.pt(cellGapMM)
        for s in sheets {
            let a = area(of: s, margins: margins)
            for (c, r) in pairs {
                let cw = (a.width - gap * Double(c - 1)) / Double(c)
                let ch = (a.height - gap * Double(r - 1)) / Double(r)
                guard cw > 0, ch > 0, page.width > 0, page.height > 0 else { continue }
                let scale = min(cw / page.width, ch / page.height)
                if best == nil || scale > best!.1 + 1e-9 {
                    best = (Grid(columns: c, rows: r, sheet: s), scale)
                }
            }
        }
        return best?.0 ?? Grid(columns: 1, rows: n, sheet: sheet.portrait)
    }

    /// Ячейки по порядку чтения: Z — строками сверху вниз, N — столбцами слева направо.
    public static func gridCells(area a: LayoutRect, columns: Int, rows: Int, order: NUpOrder) -> [LayoutRect] {
        let gap = Units.pt(cellGapMM)
        let cw = (a.width - gap * Double(columns - 1)) / Double(columns)
        let ch = (a.height - gap * Double(rows - 1)) / Double(rows)
        func cell(_ col: Int, _ row: Int) -> LayoutRect {
            // row 0 — верхняя строка.
            LayoutRect(x: a.x + Double(col) * (cw + gap), y: a.maxY - Double(row + 1) * ch - Double(row) * gap,
                       width: cw, height: ch)
        }
        var result: [LayoutRect] = []
        switch order {
        case .rows:
            for r in 0..<rows { for c in 0..<columns { result.append(cell(c, r)) } }
        case .columns:
            for c in 0..<columns { for r in 0..<rows { result.append(cell(c, r)) } }
        }
        return result
    }

    private static func noteLines(in rect: LayoutRect) -> [LayoutLine] {
        let step = Units.pt(7)
        var lines: [LayoutLine] = []
        var y = rect.maxY - step
        while y > rect.minY + Units.pt(2) {
            lines.append(LayoutLine(x1: rect.minX, y1: y, x2: rect.maxX, y2: y, width: 0.4))
            y -= step
        }
        return lines
    }

    static func rectLines(_ r: LayoutRect, width: Double) -> [LayoutLine] {
        [LayoutLine(x1: r.minX, y1: r.minY, x2: r.maxX, y2: r.minY, width: width),
         LayoutLine(x1: r.maxX, y1: r.minY, x2: r.maxX, y2: r.maxY, width: width),
         LayoutLine(x1: r.maxX, y1: r.maxY, x2: r.minX, y2: r.maxY, width: width),
         LayoutLine(x1: r.minX, y1: r.maxY, x2: r.minX, y2: r.minY, width: width)]
    }

    // MARK: Страница в ячейке

    /// «Заменить поля»: белые поля исходника срезаются, содержимое прижимается к новым полям.
    static func replaceMode(_ settings: PrintSettings) -> Bool {
        settings.marginsActive && !settings.marginsAdd
    }

    /// Какой кусок страницы берём: вся страница или её непустая часть.
    static func crop(for page: Int, source: LayoutSource, settings: PrintSettings) -> LayoutRect {
        let full = LayoutRect(size: source.pageSize(page))
        guard settings.trimWhite || replaceMode(settings) else { return full }
        guard let box = source.contentBox(page), !box.isEmpty else { return full }
        let clipped = box.intersection(full)
        return clipped.isEmpty ? full : clipped
    }

    static func place(_ slot: PageSlot, in cell: LayoutRect, source: LayoutSource, settings: PrintSettings,
                      single: Bool) -> SidePlacement? {
        guard case .page(let p) = slot, cell.width > 0, cell.height > 0 else { return nil }
        let c = crop(for: p, source: source, settings: settings)
        guard c.width > 0, c.height > 0 else { return nil }
        let replace = replaceMode(settings) && single
        var scale: Double
        switch settings.scaleMode {
        case .fit:
            scale = min(cell.width / c.width, cell.height / c.height)
            // В режиме «заменить поля» текст не увеличиваем: кегль остаётся как в файле.
            if replace { scale = min(scale, 1) }
        case .actual:
            scale = 1
        case .custom:
            scale = Double(min(max(settings.customScale, 10), 400)) / 100
        }
        let w = c.width * scale, h = c.height * scale
        let target: LayoutRect
        if replace && settings.scaleMode == .fit {
            // Прижать к левому верхнему углу поля: слева ровно заданное поле, сверху тоже.
            target = LayoutRect(x: cell.minX, y: cell.maxY - h, width: w, height: h)
        } else {
            target = LayoutRect(x: cell.midX - w / 2, y: cell.midY - h / 2, width: w, height: h)
        }
        return SidePlacement(slot: slot, cell: cell, crop: c, target: target, scale: scale)
    }

    // MARK: Брошюра

    private static func bookletSides(slots: [PageSlot], source: LayoutSource, settings: PrintSettings,
                                     sheet: LayoutSize) -> [SideLayout] {
        // Номера логических позиций → план брошюры → обратно в ячейки.
        let positions = Array(1...slots.count)
        let plan = BookletPlanner.plan(pages: positions, reverseBacks: false)
        let land = sheet.landscape
        let half = LayoutRect(x: 0, y: 0, width: land.width / 2, height: land.height)
        var m = settings.margins.clamped.atLeast(PageMargins(all: bookletMinMarginMM))
        if settings.fileHeader { m.top = max(m.top, 10) }
        let leftArea = half.inset(top: Units.pt(m.top), left: Units.pt(m.left), bottom: Units.pt(m.bottom), right: Units.pt(m.right))
        let rightArea = LayoutRect(x: leftArea.x + land.width / 2, y: leftArea.y, width: leftArea.width, height: leftArea.height)
        var noMargins = settings
        noMargins.margins = .zero
        noMargins.gutter = 0
        func resolve(_ s: PageSlot) -> PageSlot {
            if case .page(let pos) = s { return slots[pos - 1] }
            return .blank
        }
        func side(_ b: BookletSide, isBack: Bool) -> SideLayout {
            var placements: [SidePlacement] = []
            var lines: [LayoutLine] = []
            for (slot, cellArea) in [(resolve(b.left), leftArea), (resolve(b.right), rightArea)] {
                var cell = cellArea
                if settings.numbering.enabled { cell = cell.inset(top: 0, left: 0, bottom: Units.pt(4.5), right: 0) }
                if let p = place(slot, in: cell, source: source, settings: noMargins, single: false) {
                    placements.append(p)
                } else {
                    placements.append(SidePlacement(slot: .blank, cell: cell, crop: LayoutRect(x: 0, y: 0, width: 0, height: 0),
                                                    target: cell, scale: 1))
                }
                if settings.cellBorders { lines += rectLines(cellArea, width: 0.5) }
            }
            return SideLayout(size: land, area: leftArea.union(rightArea), placements: placements,
                              lines: lines, labels: [], isBack: isBack)
        }
        return plan.sheets.flatMap { [side($0.front, isBack: false), side($0.back, isBack: true)] }
    }

    // MARK: Надписи и рамки

    private static func addOverlays(_ sides: inout [SideLayout], settings: PrintSettings, source: LayoutSource) {
        let total = sides.count
        let n = settings.booklet ? 2 : perSheet(settings)
        for i in sides.indices {
            var side = sides[i]
            let sheet = LayoutRect(size: side.size)
            let margins = settings.booklet ? settings.margins : effectiveMargins(settings, isBack: side.isBack)

            // Номера страниц.
            if settings.numbering.enabled {
                if n == 1 && !settings.eskdTitleBlock {
                    for p in side.placements {
                        guard case .page(let page) = p.slot, let text = settings.numbering.label(forPage: page) else { continue }
                        side.labels.append(numberLabel(text, sheet: sheet, area: side.area, margins: margins,
                                                       position: settings.numbering.position))
                    }
                } else if n > 1 {
                    for p in side.placements {
                        guard case .page(let page) = p.slot, let text = settings.numbering.label(forPage: page) else { continue }
                        let x: Double, align: LabelAlignment
                        switch settings.numbering.position {
                        case .bottomCenter: x = p.cell.midX; align = .center
                        case .bottomRight, .topRight: x = p.cell.maxX; align = .right
                        }
                        side.labels.append(SideLabel(text: text, x: x, y: p.cell.minY - Units.pt(2.3), alignment: align, fontSize: 7))
                    }
                }
            }

            // Колонтитул.
            if settings.fileHeader {
                let y = sheet.maxY - Units.pt(max(min(margins.top / 2, 7), 4))
                if let header = source.headerText, !header.isEmpty {
                    side.labels.append(SideLabel(text: header, x: side.area.minX, y: y, alignment: .left, fontSize: 7))
                }
                if !(settings.numbering.enabled && settings.numbering.position == .topRight) {
                    side.labels.append(SideLabel(text: "\(i + 1) / \(total)", x: side.area.maxX, y: y,
                                                 alignment: .right, fontSize: 7, monospaced: true))
                }
            }

            // Рамка ЕСКД и основная надпись.
            if settings.eskdFrame || settings.eskdTitleBlock {
                let f = eskdFrameMM
                let frame = sheet.inset(top: Units.pt(f.top), left: Units.pt(f.left), bottom: Units.pt(f.bottom), right: Units.pt(f.right))
                side.lines += rectLines(frame, width: Units.pt(0.6))
                if settings.eskdTitleBlock {
                    let sheetNo: String = {
                        if n == 1, let p = side.placements.first, case .page(let page) = p.slot {
                            if settings.numbering.enabled { return settings.numbering.label(forPage: page) ?? "" }
                            return String(page)
                        }
                        return String(i + 1)
                    }()
                    let block = EskdForm2a.layout(frame: frame, designation: settings.eskdDesignation, sheetNumber: sheetNo)
                    side.lines += block.lines
                    side.labels += block.labels
                }
            }
            sides[i] = side
        }
    }

    static func numberLabel(_ text: String, sheet: LayoutRect, area: LayoutRect, margins: PageMargins,
                            position: NumberPosition) -> SideLabel {
        let size = 12.0
        switch position {
        case .bottomCenter:
            return SideLabel(text: text, x: area.midX, y: Units.pt(max(margins.bottom / 2, 5)), alignment: .center, fontSize: size)
        case .bottomRight:
            return SideLabel(text: text, x: area.maxX, y: Units.pt(max(margins.bottom / 2, 5)), alignment: .right, fontSize: size)
        case .topRight:
            return SideLabel(text: text, x: area.maxX, y: sheet.maxY - Units.pt(max(margins.top / 2, 5)), alignment: .right, fontSize: size)
        }
    }
}

extension LayoutRect {
    var sizeValue: LayoutSize { LayoutSize(width: width, height: height) }
}

/// Основная надпись по форме 2а (последующие листы текстовых документов), 185×15 мм.
/// Графы слева направо: 7, 10, 23, 15, 10 (три строки по 5 мм), 110 (обозначение), 10 («Лист»: 7 мм + 8 мм).
/// Размеры — по ГОСТ 2.104-2006 и рисунку 3.1 «в» в СТП БГУИР 01-2024.
public enum EskdForm2a {
    public static let columnsMM: [Double] = [7, 10, 23, 15, 10, 110, 10]
    public static let headers = ["Изм.", "Лист", "№ докум.", "Подп.", "Дата"]

    public static func layout(frame: LayoutRect, designation: String, sheetNumber: String) -> (lines: [LayoutLine], labels: [SideLabel]) {
        let mm = Units.pointsPerMM
        let thick = 0.6 * mm, thin = 0.25 * mm
        let w = LayoutPlanner.titleBlockWidthMM * mm, h = LayoutPlanner.titleBlockHeightMM * mm
        let rect = LayoutRect(x: frame.maxX - w, y: frame.minY, width: w, height: h)
        var lines = LayoutPlanner.rectLines(rect, width: thick)
        var x = rect.minX
        var xs: [Double] = [x]
        for c in columnsMM { x += c * mm; xs.append(x) }
        for vx in xs.dropFirst().dropLast() {
            lines.append(LayoutLine(x1: vx, y1: rect.minY, x2: vx, y2: rect.maxY, width: thick))
        }
        // Строки левой части (5 мм) — тонкие.
        let leftEnd = xs[5]
        for k in 1...2 {
            let y = rect.minY + Double(k) * 5 * mm
            lines.append(LayoutLine(x1: rect.minX, y1: y, x2: leftEnd, y2: y, width: k == 1 ? thick : thin))
        }
        // «Лист»: сверху 7 мм подпись, снизу 8 мм номер.
        let sheetX0 = xs[6], sheetX1 = xs[7]
        lines.append(LayoutLine(x1: sheetX0, y1: rect.minY + 8 * mm, x2: sheetX1, y2: rect.minY + 8 * mm, width: thin))
        var labels: [SideLabel] = []
        for (i, title) in headers.enumerated() {
            labels.append(SideLabel(text: title, x: (xs[i] + xs[i + 1]) / 2, y: rect.minY + 2.5 * mm,
                                    alignment: .center, fontSize: 5.5))
        }
        labels.append(SideLabel(text: "Лист", x: (sheetX0 + sheetX1) / 2, y: rect.minY + 11.5 * mm, alignment: .center, fontSize: 6))
        if !sheetNumber.isEmpty {
            labels.append(SideLabel(text: sheetNumber, x: (sheetX0 + sheetX1) / 2, y: rect.minY + 4 * mm, alignment: .center, fontSize: 10))
        }
        let d = designation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty {
            labels.append(SideLabel(text: d, x: (xs[5] + xs[6]) / 2, y: rect.midY, alignment: .center, fontSize: 13))
        }
        return (lines, labels)
    }
}

/// Поиск непустой области на растровом снимке страницы (для обрезки белых полей).
public enum ContentBounds {
    /// - Parameters:
    ///   - gray: яркость пикселей построчно, первая строка — верх страницы (0 — чёрный, 255 — белый).
    ///   - threshold: всё, что темнее, считается содержимым.
    ///   - minDark: сколько тёмных пикселей нужно в строке/столбце, чтобы не считать это пылинкой.
    /// - Returns: прямоугольник в пикселях с началом слева снизу или nil для пустой страницы.
    public static func detect(gray: [UInt8], width: Int, height: Int, threshold: UInt8 = 235, minDark: Int = 2) -> LayoutRect? {
        guard width > 0, height > 0, gray.count >= width * height else { return nil }
        var rowCounts = [Int](repeating: 0, count: height)
        var colCounts = [Int](repeating: 0, count: width)
        for y in 0..<height {
            let base = y * width
            for x in 0..<width where gray[base + x] < threshold {
                rowCounts[y] += 1
                colCounts[x] += 1
            }
        }
        guard let top = rowCounts.firstIndex(where: { $0 >= minDark }),
              let bottom = rowCounts.lastIndex(where: { $0 >= minDark }),
              let left = colCounts.firstIndex(where: { $0 >= minDark }),
              let right = colCounts.lastIndex(where: { $0 >= minDark }) else { return nil }
        // Переворачиваем ось Y: в PDF начало снизу.
        return LayoutRect(x: Double(left), y: Double(height - 1 - bottom),
                          width: Double(right - left + 1), height: Double(bottom - top + 1))
    }

    /// Из пикселей снимка в пункты страницы, с запасом `paddingMM` со всех сторон.
    public static func toPage(_ px: LayoutRect, pixelsPerPoint: Double, page: LayoutSize, paddingMM: Double = 1) -> LayoutRect {
        let pad = Units.pt(paddingMM)
        let r = LayoutRect(x: px.x / pixelsPerPoint - pad, y: px.y / pixelsPerPoint - pad,
                           width: px.width / pixelsPerPoint + 2 * pad, height: px.height / pixelsPerPoint + 2 * pad)
        return r.intersection(LayoutRect(size: page))
    }

    /// Общая рамка для страниц одного размера: тогда текст на всех листах стоит одинаково.
    public static func unified(_ boxes: [Int: LayoutRect], sizes: [Int: LayoutSize]) -> [Int: LayoutRect] {
        func key(_ s: LayoutSize) -> String { "\(Int(s.width.rounded()))x\(Int(s.height.rounded()))" }
        var unions: [String: LayoutRect] = [:]
        for (page, box) in boxes {
            guard let size = sizes[page] else { continue }
            let k = key(size)
            unions[k] = unions[k].map { $0.union(box) } ?? box
        }
        var result: [Int: LayoutRect] = [:]
        for (page, size) in sizes {
            if let u = unions[key(size)] { result[page] = u }
        }
        return result
    }
}

extension LayoutPlanner {
    /// Сколько страниц на стороне листа на самом деле (для схем в интерфейсе).
    public static func perSheetPublic(_ settings: PrintSettings) -> Int { perSheet(settings) }
}
