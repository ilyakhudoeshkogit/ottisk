import Foundation

/// Пресеты «одной кнопкой».
public enum PrintPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case economy
    case draft
    case manualDuplex
    case multiPage
    // v0.4: учёба и работа
    case gost
    case bsuir
    case eskdFrame
    case lectureNotes
    case bookletManual
    case paperSaver
    case signDocument
    case slides
    case passport

    public enum Group: String, CaseIterable, Sendable {
        case quick, study
        public var title: String {
            switch self {
            case .quick: return "Быстрые"
            case .study: return "Учёба и работа"
            }
        }
    }

    public var id: String { rawValue }

    public var group: Group {
        switch self {
        case .normal, .economy, .draft, .manualDuplex, .multiPage: return .quick
        default: return .study
        }
    }

    public static func presets(in group: Group) -> [PrintPreset] { allCases.filter { $0.group == group } }

    public var title: String {
        switch self {
        case .normal: return "Обычно"
        case .economy: return "Экономия тонера"
        case .draft: return "Черновик"
        case .manualDuplex: return "С двух сторон"
        case .multiPage: return "2 на листе"
        case .gost: return "ГОСТ / курсовая"
        case .bsuir: return "БГУИР (СТП)"
        case .eskdFrame: return "Рамка ЕСКД"
        case .lectureNotes: return "Конспект"
        case .bookletManual: return "Брошюра-методичка"
        case .paperSaver: return "Экономия бумаги"
        case .signDocument: return "На подпись"
        case .slides: return "Слайды лекции"
        case .passport: return "Скан паспорта"
        }
    }

    public var subtitle: String {
        switch self {
        case .normal: return "Как есть, по размеру листа"
        case .economy: return "Бледнее, тонер живёт дольше"
        case .draft: return "Быстро и экономно, 2 стр. на листе"
        case .manualDuplex: return "Нечётные, переворот, чётные"
        case .multiPage: return "Две страницы на одном листе"
        case .gost: return "Поля 30/15/20/20 мм, номер внизу по центру, титул без номера"
        case .bsuir: return "Поля как в ГОСТ, номер справа внизу, титул без номера"
        case .eskdFrame: return "Рамка 20/5/5/5 мм и штамп 185×15 с номером листа"
        case .lectureNotes: return "4 страницы на листе, белые поля исходника срезаны"
        case .bookletManual: return "A5-книжечка из A4: печать в 2 прохода, сложить пополам"
        case .paperSaver: return "2 на стороне и с двух сторон: 4 страницы на лист"
        case .signDocument: return "100 %, без масштаба; только 1-я страница или твой диапазон"
        case .slides: return "4 слайда на листе, справа линии для заметок"
        case .passport: return "Реальный размер по DPI скана, по центру, чуть контрастнее"
        }
    }

    /// Имя SF Symbol для кнопки.
    public var symbol: String {
        switch self {
        case .normal: return "doc"
        case .economy: return "leaf"
        case .draft: return "pencil.and.scribble"
        case .manualDuplex: return "arrow.triangle.2.circlepath"
        case .multiPage: return "rectangle.split.2x1"
        case .gost: return "graduationcap"
        case .bsuir: return "building.columns"
        case .eskdFrame: return "rectangle.inset.filled"
        case .lectureNotes: return "square.grid.2x2"
        case .bookletManual: return "book"
        case .paperSaver: return "doc.on.doc"
        case .signDocument: return "signature"
        case .slides: return "list.bullet.rectangle"
        case .passport: return "person.text.rectangle"
        }
    }

    /// Применяет пресет, сохраняя копии, диапазон, размер бумаги, ориентацию и плотность тонера.
    public func apply(to base: PrintSettings) -> PrintSettings {
        var s = PrintSettings()
        s.copies = base.copies
        s.pageRange = base.pageRange
        s.mediaSize = base.mediaSize
        s.orientation = base.orientation
        s.tonerDensity = base.tonerDensity
        s.eskdDesignation = base.eskdDesignation
        switch self {
        case .normal:
            break
        case .economy:
            s.tonerSave = true
        case .draft:
            s.quality = .draft
            s.tonerSave = true
            s.pagesPerSheet = 2
        case .manualDuplex:
            s.manualDuplex = true
        case .multiPage:
            s.pagesPerSheet = 2
        case .gost:
            // ГОСТ 7.32-2017: п. 6.1.1 (поля), п. 6.3.1–6.3.2 (номер в центре внизу, на титуле не ставится).
            s.margins = .gost7_32
            s.numbering = PageNumbering(enabled: true, startAt: 1, skipFirst: 1, position: .bottomCenter)
        case .bsuir:
            // СТП БГУИР 01-2024: п. 2.1.1 (поля), п. 2.2.8 (номер в правом нижнем углу;
            // титул, реферат и задание без номера — сколько их, задаётся в «Ещё»).
            s.margins = .gost7_32
            s.numbering = PageNumbering(enabled: true, startAt: 1, skipFirst: 1, position: .bottomRight)
        case .eskdFrame:
            s.eskdFrame = true
            s.eskdTitleBlock = true
            s.margins = LayoutPlanner.eskdTextMargins(titleBlock: true)
            s.numbering = PageNumbering(enabled: true, startAt: 1, skipFirst: 0, position: .bottomRight)
        case .lectureNotes:
            s.pagesPerSheet = 4
            s.margins = PageMargins(all: 5)
            s.marginsAdd = true
            s.trimWhite = true
        case .bookletManual:
            s.booklet = true
            s.trimWhite = true
        case .paperSaver:
            s.pagesPerSheet = 2
            s.manualDuplex = true
        case .signDocument:
            s.scaleMode = .actual
            if base.pageRange.trimmingCharacters(in: .whitespaces).isEmpty { s.pageRange = "1" }
        case .slides:
            s.pagesPerSheet = 4
            s.slideNotes = true
            s.cellBorders = true
            s.margins = PageMargins(all: 8)
            s.marginsAdd = true
        case .passport:
            s.scaleMode = .actual
            s.contrastBoost = 1
        }
        return s
    }

    /// Какой пресет соответствует настройкам (для подсветки кнопки), если ровно совпадает.
    public static func matching(_ settings: PrintSettings) -> PrintPreset? {
        allCases.first { $0.apply(to: settings) == settings }
    }
}

/// Поиск подходящих опций в PPD-драйвере (вывод `lpoptions -l`).
public enum DriverOptionMatcher {
    private static let offWords: Set<String> = ["off", "false", "no", "none", "printerdefault", "default", "0", "disable", "disabled"]
    private static let onWords: [String] = ["on", "true", "yes", "1", "enable", "enabled", "economy", "eco", "save", "tonersave", "low"]

    /// Опция экономии тонера, если драйвер её даёт (названия у производителей разные).
    public static func tonerSave(in options: [PrinterOption]) -> (key: String, value: String)? {
        let candidates = options.filter { opt in
            let k = opt.key.lowercased()
            let l = opt.label.lowercased()
            let text = k + " " + l
            if k == "economode" || k == "econmode" || k == "tonersave" || k == "tonersaving" || k == "cntonersaving" { return true }
            if text.contains("toner") && (text.contains("sav") || text.contains("econ")) { return true }
            if text.contains("econo") && !text.contains("speed") { return true }
            return false
        }
        for opt in candidates {
            // Сначала явные «включено».
            for word in onWords {
                if let choice = opt.choices.first(where: { $0.lowercased() == word }) {
                    return (opt.key, choice)
                }
            }
            // Иначе любое значение, которое не «выключено».
            if let choice = opt.choices.first(where: { !offWords.contains($0.lowercased()) }) {
                return (opt.key, choice)
            }
        }
        return nil
    }

    /// Дополнительные опции для черновика: явное Draft-качество и минимальное разрешение.
    public static func draft(in options: [PrinterOption]) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        for opt in options {
            let k = opt.key.lowercased()
            if k.contains("quality") || k.contains("printmode") {
                if let choice = opt.choices.first(where: { $0.lowercased().contains("draft") || $0.lowercased() == "fast" }) {
                    result.append((opt.key, choice))
                }
            }
        }
        if let res = options.first(where: { $0.key == "Resolution" }), res.choices.count > 1 {
            let withDPI = res.choices.compactMap { choice -> (String, Int)? in
                let digits = choice.prefix { $0.isNumber }
                guard let v = Int(digits) else { return nil }
                return (choice, v)
            }
            if let lowest = withDPI.min(by: { $0.1 < $1.1 }), lowest.0 != res.defaultChoice {
                result.append((res.key, lowest.0))
            }
        }
        return result
    }

    public static func resolve(_ options: [PrinterOption]) -> ResolvedDriverOptions {
        ResolvedDriverOptions(tonerSave: tonerSave(in: options), draft: draft(in: options), density: density(in: options))
    }

    /// Плотность тонера («Density», «TonerDensity», «Darkness», «CNTonerDensity»…), если есть в драйвере.
    public static func density(in options: [PrinterOption]) -> PrinterOption? {
        options.first { opt in
            let text = (opt.key + " " + opt.label).lowercased()
            return (text.contains("density") || text.contains("darkness") || text.contains("плотност"))
                && opt.choices.count > 1
        }
    }

    /// Варианты размера бумаги (`PageSize` или `media`).
    public static func mediaOption(in options: [PrinterOption]) -> PrinterOption? {
        options.first { $0.key == "PageSize" } ?? options.first { $0.key == "media" }
    }
}
