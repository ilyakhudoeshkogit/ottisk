import Foundation

/// Состояние одного документа в очереди «Печатать все».
public enum QueueItemState: Equatable, Sendable {
    case waiting
    case printing
    /// Первая сторона ушла, ждём, пока пользователь перевернёт пачку (DuplexGate) и отправит оборот.
    case awaitingFlip
    case done
    case failed(String)
    /// Пропущен (очередь остановлена или диапазон неверный).
    case skipped
}

/// Документ очереди: либо «как общий пресет», либо со своими копиями и диапазоном.
public struct QueueItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var pageCount: Int
    /// false — берём общие настройки (копии из пресета, все страницы).
    public var hasOverride = false
    public var copies = 1
    public var pageRange = ""
    public var state: QueueItemState = .waiting

    public init(id: UUID = UUID(), name: String, pageCount: Int) {
        self.id = id
        self.name = name
        self.pageCount = pageCount
    }

    /// Страницы документа, которые надо напечатать (с 1).
    public func pages() throws -> [Int] {
        try PageRange.parse(hasOverride ? pageRange : "", pageCount: pageCount)
    }

    public var rangeError: String? {
        do { _ = try pages(); return nil } catch let e as PageRange.ParseError { return e.description } catch { return "?" }
    }

    /// Настройки для печати этого документа: общий пресет, у «своих» подменяются копии и диапазон.
    /// Диапазон общих настроек относится к одному документу, поэтому в очереди он сбрасывается.
    public func effectiveSettings(shared: PrintSettings) -> PrintSettings {
        var s = shared
        s.pageRange = ""
        if hasOverride {
            s.copies = min(max(copies, 1), 99)
            s.pageRange = pageRange
        }
        return s
    }

    public var isFinished: Bool {
        switch state {
        case .done, .failed, .skipped: return true
        default: return false
        }
    }
}

/// Данные документа для синхронизации очереди со списком слева.
public struct QueueDocumentInfo: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let pageCount: Int
    public init(id: UUID, name: String, pageCount: Int) {
        self.id = id
        self.name = name
        self.pageCount = pageCount
    }
}

/// Страница склеенного PDF: какой документ и какая страница (с 1).
public struct MergedPage: Equatable, Sendable {
    public let itemID: UUID
    public let page: Int
}

/// Что делать очереди дальше.
public enum QueueStep: Equatable, Sendable {
    case print(UUID)
    /// Ждём оборота пачки по предыдущему документу — следующий не отправляем.
    case waitForFlip(UUID)
    case finished
}

/// Логика очереди нескольких документов: порядок, состояния, склейка, «что дальше».
public struct PrintQueue: Equatable, Sendable {
    public var items: [QueueItem] = []
    /// Склеить все документы в один PDF и отправить одним заданием.
    public var mergeIntoOne = false
    public private(set) var isRunning = false

    public init() {}

    // MARK: Список

    /// Привести очередь в соответствие со списком документов (порядок — как в списке).
    /// Настройки и состояния оставшихся документов сохраняются.
    public mutating func sync(with docs: [QueueDocumentInfo]) {
        var old = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = docs.map { doc in
            if var item = old.removeValue(forKey: doc.id) {
                item.name = doc.name
                item.pageCount = doc.pageCount
                return item
            }
            return QueueItem(id: doc.id, name: doc.name, pageCount: doc.pageCount)
        }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isRunning else { return }
        let moving = source.sorted().map { items[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { items.remove(at: index) }
        items.insert(contentsOf: moving, at: min(max(destination - before, 0), items.count))
    }

    public mutating func remove(_ id: UUID) {
        guard !isRunning else { return }
        items.removeAll { $0.id == id }
    }

    public func item(_ id: UUID) -> QueueItem? { items.first { $0.id == id } }

    public mutating func update(_ id: UUID, _ change: (inout QueueItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    // MARK: Запуск и шаги

    /// Документы, которые будут напечатаны (ещё не завершённые, с верным диапазоном).
    public var printable: [QueueItem] {
        items.filter { $0.state == .waiting && $0.rangeError == nil }
    }

    /// Можно запускать (в том числе повторно: start() сбросит прошлые состояния).
    public var canStart: Bool { !isRunning && items.contains { $0.rangeError == nil } }

    /// Начать: сбросить завершённые в «ждёт», неверные диапазоны пометить пропущенными.
    public mutating func start() {
        guard !isRunning else { return }
        for i in items.indices {
            items[i].state = items[i].rangeError == nil ? .waiting : .skipped
        }
        isRunning = !printable.isEmpty
    }

    public func nextStep() -> QueueStep {
        guard isRunning else { return .finished }
        if let flip = items.first(where: { $0.state == .awaitingFlip }) { return .waitForFlip(flip.id) }
        if let next = items.first(where: { $0.state == .waiting }) { return .print(next.id) }
        if items.contains(where: { $0.state == .printing }) { return .finished }
        return .finished
    }

    public mutating func markPrinting(_ id: UUID) { set(id, .printing) }
    public mutating func markAwaitingFlip(_ id: UUID) { set(id, .awaitingFlip) }
    public mutating func markDone(_ id: UUID) { set(id, .done) }
    public mutating func markFailed(_ id: UUID, _ message: String) { set(id, .failed(message)) }

    private mutating func set(_ id: UUID, _ state: QueueItemState) {
        update(id) { $0.state = state }
    }

    /// Остановить: ещё не начатые документы пропускаются, текущий остаётся как есть.
    public mutating func stop() {
        for i in items.indices where items[i].state == .waiting { items[i].state = .skipped }
    }

    /// Вызывается, когда `nextStep()` вернул `.finished`.
    public mutating func finish() { isRunning = false }

    public var doneCount: Int { items.filter { $0.state == .done }.count }
    public var failedCount: Int { items.filter { if case .failed = $0.state { return true } else { return false } }.count }
    public var skippedCount: Int { items.filter { $0.state == .skipped }.count }

    // MARK: Склейка

    /// Страницы всех печатаемых документов подряд. У документа со своими копиями страницы
    /// повторяются целиком (1-2, 1-2); общие копии пресета задаёт само задание.
    public func mergedPages() -> [MergedPage] {
        var result: [MergedPage] = []
        for item in printable {
            guard let pages = try? item.pages() else { continue }
            let repeats = item.hasOverride ? min(max(item.copies, 1), 99) : 1
            for _ in 0..<repeats { result += pages.map { MergedPage(itemID: item.id, page: $0) } }
        }
        return result
    }

    /// Настройки склеенного задания: общий пресет, диапазон не нужен (уже выбран при склейке),
    /// копии ставит пресет на всё задание целиком.
    public static func mergedSettings(shared: PrintSettings) -> PrintSettings {
        var s = shared
        s.pageRange = ""
        return s
    }
}
