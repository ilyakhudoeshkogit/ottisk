import Foundation

public enum PageOrientation: String, Codable, CaseIterable, Sendable {
    case auto, portrait, landscape

    public var title: String {
        switch self {
        case .auto: return "Авто"
        case .portrait: return "Книжная"
        case .landscape: return "Альбомная"
        }
    }
}

public enum PrintQuality: String, Codable, CaseIterable, Sendable {
    case normal, draft
}

/// Все настройки одного задания — то, что видно в правой панели.
public struct PrintSettings: Codable, Equatable, Hashable, Sendable {
    public var copies: Int = 1
    /// Как ввёл человек: «1-3, 5». Пусто — все страницы.
    public var pageRange: String = ""
    /// 1, 2, 4, 6, 9, 16.
    public var pagesPerSheet: Int = 1
    public var collate: Bool = true
    public var orientation: PageOrientation = .auto
    public var quality: PrintQuality = .normal
    public var tonerSave: Bool = false
    public var manualDuplex: Bool = false
    public var reverseOrder: Bool = false
    /// Значение опции `media`/`PageSize`, например `A4`. nil — по умолчанию принтера.
    public var mediaSize: String?
    /// Брошюра: страницы раскладываются по 2 на сторону альбомного листа так,
    /// чтобы пачку можно было согнуть пополам. Печатается в два прохода, как ручная двусторонняя.
    public var booklet: Bool = false

    // MARK: v0.4 — раскладка делается в самом Оттиске (PDF), поэтому превью = печать.

    /// Масштаб страницы в ячейке.
    public var scaleMode: ScaleMode = .fit
    /// Процент для `.custom` (10…400).
    public var customScale: Int = 100
    /// Поля листа, мм.
    public var margins: PageMargins = .zero
    /// false — «заменить»: белые поля исходника обрезаются, содержимое ставится в новые поля
    /// (слева гарантированно не меньше заданного). true — «добавить»: вся страница
    /// вместе со своими полями уменьшается и встаёт внутрь новых полей.
    public var marginsAdd: Bool = false
    /// Поле под переплёт, мм (прибавляется к полю со стороны переплёта).
    public var gutter: Double = 0
    public var gutterEdge: BindingEdge = .left
    /// Зеркальные поля: на оборотах поле переплёта переезжает на другую сторону.
    public var mirrorMargins: Bool = false
    public var parity: PageParity = .all
    /// Каждая страница N раз подряд (2 + «2 на листе» = две копии на одном листе).
    public var repeatEach: Int = 1
    /// Пустая страница после каждых N страниц (0 — нет).
    public var blankEvery: Int = 0
    /// Пустой лист между копиями.
    public var blankBetweenCopies: Bool = false
    public var numbering = PageNumbering()
    /// Колонтитул сверху: имя файла, дата, «лист X из Y».
    public var fileHeader: Bool = false
    /// Рамка вокруг каждой страницы при «N на листе» и в брошюре.
    public var cellBorders: Bool = false
    public var nUpOrder: NUpOrder = .rows
    /// Обрезать белые поля исходника (общая рамка по всем страницам).
    public var trimWhite: Bool = false
    /// Для сканов: утолщение тонких линий, 0…3.
    public var thickenLines: Int = 0
    /// Для сканов: контраст, 0…3.
    public var contrastBoost: Int = 0
    /// Рамка по ГОСТ 2.104 (поле 20 мм слева, 5 мм с остальных сторон).
    public var eskdFrame: Bool = false
    /// Основная надпись по форме 2а (185×15 мм) с номером листа.
    public var eskdTitleBlock: Bool = false
    /// Обозначение документа в основной надписи, например «ГУИР.400201.001 ПЗ».
    public var eskdDesignation: String = ""
    /// Слайды: в строке слайд слева, линии для заметок справа.
    public var slideNotes: Bool = false
    /// Значение опции плотности тонера из драйвера (nil — как в драйвере).
    public var tonerDensity: String?

    public init() {}

    /// Совместимость со старым кодом и пресетами: «Вписать в лист».
    public var fitToPage: Bool {
        get { scaleMode == .fit }
        set { scaleMode = newValue ? .fit : .actual }
    }

    private enum CodingKeys: String, CodingKey {
        case copies, pageRange, pagesPerSheet, collate, orientation, fitToPage, quality,
             tonerSave, manualDuplex, reverseOrder, mediaSize, booklet,
             scaleMode, customScale, margins, marginsAdd, gutter, gutterEdge, mirrorMargins, parity,
             repeatEach, blankEvery, blankBetweenCopies, numbering, fileHeader, cellBorders, nUpOrder,
             trimWhite, thickenLines, contrastBoost, eskdFrame, eskdTitleBlock, eskdDesignation,
             slideNotes, tonerDensity
    }

    /// Терпимое чтение: отсутствующие поля (например, в пресетах из старой версии)
    /// берутся по умолчанию, а не ломают весь файл.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrintSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        copies = v(.copies, d.copies)
        pageRange = v(.pageRange, d.pageRange)
        pagesPerSheet = v(.pagesPerSheet, d.pagesPerSheet)
        collate = v(.collate, d.collate)
        orientation = v(.orientation, d.orientation)
        quality = v(.quality, d.quality)
        tonerSave = v(.tonerSave, d.tonerSave)
        manualDuplex = v(.manualDuplex, d.manualDuplex)
        reverseOrder = v(.reverseOrder, d.reverseOrder)
        mediaSize = (try? c.decodeIfPresent(String.self, forKey: .mediaSize)) ?? nil
        booklet = v(.booklet, d.booklet)
        if let mode = (try? c.decodeIfPresent(ScaleMode.self, forKey: .scaleMode)) ?? nil {
            scaleMode = mode
        } else if let fit = (try? c.decodeIfPresent(Bool.self, forKey: .fitToPage)) ?? nil {
            scaleMode = fit ? .fit : .actual
        }
        customScale = v(.customScale, d.customScale)
        margins = v(.margins, d.margins)
        marginsAdd = v(.marginsAdd, d.marginsAdd)
        gutter = v(.gutter, d.gutter)
        gutterEdge = v(.gutterEdge, d.gutterEdge)
        mirrorMargins = v(.mirrorMargins, d.mirrorMargins)
        parity = v(.parity, d.parity)
        repeatEach = v(.repeatEach, d.repeatEach)
        blankEvery = v(.blankEvery, d.blankEvery)
        blankBetweenCopies = v(.blankBetweenCopies, d.blankBetweenCopies)
        numbering = v(.numbering, d.numbering)
        fileHeader = v(.fileHeader, d.fileHeader)
        cellBorders = v(.cellBorders, d.cellBorders)
        nUpOrder = v(.nUpOrder, d.nUpOrder)
        trimWhite = v(.trimWhite, d.trimWhite)
        thickenLines = v(.thickenLines, d.thickenLines)
        contrastBoost = v(.contrastBoost, d.contrastBoost)
        eskdFrame = v(.eskdFrame, d.eskdFrame)
        eskdTitleBlock = v(.eskdTitleBlock, d.eskdTitleBlock)
        eskdDesignation = v(.eskdDesignation, d.eskdDesignation)
        slideNotes = v(.slideNotes, d.slideNotes)
        tonerDensity = (try? c.decodeIfPresent(String.self, forKey: .tonerDensity)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(copies, forKey: .copies)
        try c.encode(pageRange, forKey: .pageRange)
        try c.encode(pagesPerSheet, forKey: .pagesPerSheet)
        try c.encode(collate, forKey: .collate)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(fitToPage, forKey: .fitToPage)
        try c.encode(quality, forKey: .quality)
        try c.encode(tonerSave, forKey: .tonerSave)
        try c.encode(manualDuplex, forKey: .manualDuplex)
        try c.encode(reverseOrder, forKey: .reverseOrder)
        try c.encodeIfPresent(mediaSize, forKey: .mediaSize)
        try c.encode(booklet, forKey: .booklet)
        try c.encode(scaleMode, forKey: .scaleMode)
        try c.encode(customScale, forKey: .customScale)
        try c.encode(margins, forKey: .margins)
        try c.encode(marginsAdd, forKey: .marginsAdd)
        try c.encode(gutter, forKey: .gutter)
        try c.encode(gutterEdge, forKey: .gutterEdge)
        try c.encode(mirrorMargins, forKey: .mirrorMargins)
        try c.encode(parity, forKey: .parity)
        try c.encode(repeatEach, forKey: .repeatEach)
        try c.encode(blankEvery, forKey: .blankEvery)
        try c.encode(blankBetweenCopies, forKey: .blankBetweenCopies)
        try c.encode(numbering, forKey: .numbering)
        try c.encode(fileHeader, forKey: .fileHeader)
        try c.encode(cellBorders, forKey: .cellBorders)
        try c.encode(nUpOrder, forKey: .nUpOrder)
        try c.encode(trimWhite, forKey: .trimWhite)
        try c.encode(thickenLines, forKey: .thickenLines)
        try c.encode(contrastBoost, forKey: .contrastBoost)
        try c.encode(eskdFrame, forKey: .eskdFrame)
        try c.encode(eskdTitleBlock, forKey: .eskdTitleBlock)
        try c.encode(eskdDesignation, forKey: .eskdDesignation)
        try c.encode(slideNotes, forKey: .slideNotes)
        try c.encodeIfPresent(tonerDensity, forKey: .tonerDensity)
    }

    public static let allowedPagesPerSheet = [1, 2, 4, 6, 9, 16]

    /// Сколько физических листов уйдёт (без учёта копий) — грубая оценка без раскладки.
    public func sheetCount(selectedPages: Int) -> Int {
        guard selectedPages > 0 else { return 0 }
        if booklet { return BookletPlanner.sheetCount(pageCount: selectedPages) }
        let sides = Int((Double(selectedPages) / Double(max(pagesPerSheet, 1))).rounded(.up))
        return manualDuplex ? Int((Double(sides) / 2).rounded(.up)) : sides
    }

    /// Нужно ли собирать свой PDF (раскладка, поля, надписи). Если нет — исходный файл
    /// уходит в CUPS как раньше, с `fit-to-page`.
    public var needsComposition: Bool {
        pagesPerSheet > 1 || booklet || scaleMode != .fit || !margins.isZero || gutter > 0
            || parity != .all || repeatEach > 1 || blankEvery > 0 || blankBetweenCopies
            || numbering.enabled || fileHeader || cellBorders || trimWhite
            || thickenLines > 0 || contrastBoost > 0 || eskdFrame || eskdTitleBlock || slideNotes
            || reverseOrder
    }

    /// Поля включены (тогда работает «заменить/добавить»).
    public var marginsActive: Bool { !margins.isZero || gutter > 0 || eskdFrame }
}

/// Готовые опции драйвера, найденные для конкретного принтера.
public struct ResolvedDriverOptions: Equatable, Sendable {
    public var tonerSave: (key: String, value: String)?
    public var draft: [(key: String, value: String)]
    /// Опция плотности тонера, если драйвер её даёт (ключ и варианты).
    public var density: PrinterOption?

    public init(tonerSave: (key: String, value: String)? = nil, draft: [(key: String, value: String)] = [],
                density: PrinterOption? = nil) {
        self.tonerSave = tonerSave
        self.draft = draft
        self.density = density
    }

    public static func == (l: Self, r: Self) -> Bool {
        l.tonerSave?.key == r.tonerSave?.key && l.tonerSave?.value == r.tonerSave?.value
            && l.draft.map { "\($0.key)=\($0.value)" } == r.draft.map { "\($0.key)=\($0.value)" }
            && l.density == r.density
    }
}

/// Собирает аргументы для `/usr/bin/lp`.
public enum LPArgumentsBuilder {
    /// - Parameters:
    ///   - pages: выбранные страницы; nil — весь документ (без `-P`).
    ///     Для ручной двусторонней печати сюда передаётся nil, потому что
    ///     приложение заранее собирает отдельный PDF с нужными страницами.
    public static func arguments(printer: String,
                                 settings: PrintSettings,
                                 driver: ResolvedDriverOptions = .init(),
                                 title: String?,
                                 pages: [Int]?,
                                 files: [String],
                                 composed: Bool = false) -> [String] {
        var args: [String] = ["-d", printer]
        if let title, !title.isEmpty {
            args += ["-t", title]
        }
        let copies = min(max(settings.copies, 1), 999)
        if copies > 1 {
            args += ["-n", String(copies)]
            args += ["-o", "collate=\(settings.collate ? "true" : "false")"]
        }
        if let pages, !pages.isEmpty {
            args += ["-P", PageRange.cupsString(pages)]
        }
        // composed: PDF уже собран Оттиском под лист (N на листе, поля, масштаб, порядок).
        // CUPS печатает его 1:1, без своего масштабирования — иначе миллиметры ГОСТ «уплывут».
        if !composed, settings.pagesPerSheet > 1, PrintSettings.allowedPagesPerSheet.contains(settings.pagesPerSheet) {
            args += ["-o", "number-up=\(settings.pagesPerSheet)"]
            args += ["-o", "number-up-layout=lrtb"]
        }
        switch composed ? .auto : settings.orientation {
        case .auto: break
        case .portrait: args += ["-o", "orientation-requested=3"]
        case .landscape: args += ["-o", "orientation-requested=4"]
        }
        if composed {
            args += ["-o", "print-scaling=none"]
        } else if settings.fitToPage {
            args += ["-o", "fit-to-page"]
        }
        if let media = settings.mediaSize, !media.isEmpty {
            args += ["-o", "media=\(media)"]
        }
        if settings.quality == .draft {
            // IPP print-quality: 3 = draft, 4 = normal, 5 = high.
            args += ["-o", "print-quality=3"]
            for opt in driver.draft {
                args += ["-o", "\(opt.key)=\(opt.value)"]
            }
        }
        if settings.tonerSave, let toner = driver.tonerSave {
            args += ["-o", "\(toner.key)=\(toner.value)"]
        }
        if let value = settings.tonerDensity, let density = driver.density, density.choices.contains(value) {
            args += ["-o", "\(density.key)=\(value)"]
        }
        if !composed, settings.reverseOrder {
            args += ["-o", "outputorder=reverse"]
        }
        args.append("--")
        args += files
        return args
    }

    /// Строка для показа в «Подробнее» (с экранированием пробелов).
    public static func shellPreview(_ args: [String]) -> String {
        (["lp"] + args).map { arg in
            if arg.isEmpty { return "''" }
            let safe = arg.allSatisfy { $0.isLetter || $0.isNumber || "-_=.,/:".contains($0) }
            return safe ? arg : "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}
