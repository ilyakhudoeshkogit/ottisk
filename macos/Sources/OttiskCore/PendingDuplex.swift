import Foundation

/// Незавершённая ручная двусторонняя печать, сохранённая на диск.
///
/// Лицевые стороны уже отправлены, а человек закрыл Оттиск (или Mac
/// перезагрузился) до второго прохода. При следующем запуске приложение
/// предлагает допечатать оборот или отменить его.
public struct PendingDuplex: Codable, Equatable, Sendable {
    public var documentName: String
    public var printer: String
    /// Имя файла оборотных сторон в папке незавершённых заданий (не полный путь:
    /// путь к Application Support может поменяться при переносе на новый Mac).
    public var backsFileName: String
    public var sheetCount: Int
    public var frontJobID: String
    public var historyID: UUID
    public var settings: PrintSettings
    public var driver: DriverSnapshot
    public var createdAt: Date

    public init(documentName: String, printer: String, backsFileName: String, sheetCount: Int,
                frontJobID: String, historyID: UUID, settings: PrintSettings,
                driver: ResolvedDriverOptions, createdAt: Date = Date()) {
        self.documentName = documentName
        self.printer = printer
        self.backsFileName = backsFileName
        self.sheetCount = sheetCount
        self.frontJobID = frontJobID
        self.historyID = historyID
        self.settings = settings
        self.driver = DriverSnapshot(driver)
        self.createdAt = createdAt
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PendingDuplex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PendingDuplex.self, from: data)
    }
}

/// Опции драйвера в виде, который можно сохранить в JSON
/// (`ResolvedDriverOptions` хранит кортежи, а они не Codable).
public struct DriverSnapshot: Codable, Equatable, Sendable {
    public struct Pair: Codable, Equatable, Sendable {
        public var key: String
        public var value: String
    }
    public var tonerSave: Pair?
    public var draft: [Pair]
    public var densityKey: String?
    public var densityChoices: [String]?

    public init(_ options: ResolvedDriverOptions) {
        densityKey = options.density?.key
        densityChoices = options.density?.choices
        tonerSave = options.tonerSave.map { Pair(key: $0.key, value: $0.value) }
        draft = options.draft.map { Pair(key: $0.key, value: $0.value) }
    }

    public var resolved: ResolvedDriverOptions {
        ResolvedDriverOptions(tonerSave: tonerSave.map { (key: $0.key, value: $0.value) },
                              draft: draft.map { (key: $0.key, value: $0.value) },
                              density: densityKey.map { PrinterOption(key: $0, label: $0, choices: densityChoices ?? [], defaultChoice: nil) })
    }
}

/// Что делать с сохранённым заданием при запуске.
public enum PendingDuplexDecision: Equatable, Sendable {
    /// Предложить допечатать оборот.
    case offer
    /// Предложить, но предупредить: выбранного принтера сейчас нет в системе.
    case offerPrinterMissing
    /// Тихо забыть: файл оборота пропал.
    case discardMissingFile
    /// Тихо забыть: прошло слишком много времени, пачка наверняка уже не в лотке.
    case discardExpired
}

public enum PendingDuplexPolicy {
    /// Через сколько задание считается забытым (по умолчанию 7 дней).
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 3600

    public static func decide(_ pending: PendingDuplex,
                              now: Date = Date(),
                              backsFileExists: Bool,
                              availablePrinters: [String]?,
                              maxAge: TimeInterval = defaultMaxAge) -> PendingDuplexDecision {
        guard backsFileExists else { return .discardMissingFile }
        // Часы ушли назад (сменили дату) — не выбрасываем, лучше спросить.
        if now.timeIntervalSince(pending.createdAt) > maxAge { return .discardExpired }
        // Список принтеров ещё не загружен — не пугаем зря.
        guard let availablePrinters else { return .offer }
        return availablePrinters.contains(pending.printer) ? .offer : .offerPrinterMissing
    }

    /// «сегодня в 14:05», «вчера в 09:30» или «12.11 в 18:40» — для заголовка в окне.
    public static func whenText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "ru_RU")
        time.dateFormat = "HH:mm"
        let clock = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "сегодня в \(clock)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "вчера в \(clock)" }
        time.dateFormat = "dd.MM"
        return "\(time.string(from: date)) в \(clock)"
    }
}
