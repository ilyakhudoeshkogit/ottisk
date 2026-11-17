import Foundation

/// Пресет, который человек сохранил сам («Счета», «Билеты 2 копии» и т. п.).
public struct CustomPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol для кнопки.
    public var symbol: String
    public var settings: PrintSettings

    public init(id: UUID = UUID(), name: String, symbol: String = CustomPreset.defaultSymbol, settings: PrintSettings) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.settings = CustomPreset.normalized(settings)
    }

    public static let defaultSymbol = "star"
    /// Иконки на выбор в редакторе.
    public static let symbolChoices = ["star", "doc.text", "doc.on.doc", "ticket", "creditcard", "graduationcap",
                                       "briefcase", "book", "photo", "leaf", "bolt", "heart"]

    /// Диапазон страниц к пресету не относится — он свой у каждого документа.
    static func normalized(_ settings: PrintSettings) -> PrintSettings {
        var s = settings
        s.pageRange = ""
        return s
    }

    /// Применяет пресет: всё из пресета, кроме диапазона страниц (он остаётся от документа).
    public func apply(to base: PrintSettings) -> PrintSettings {
        var s = settings
        s.pageRange = base.pageRange
        return s
    }

    public func matches(_ current: PrintSettings) -> Bool {
        apply(to: current) == current
    }
}

/// Список своих пресетов и все правила работы с ним. Без файлов и UI — только логика.
public struct PresetLibrary: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case emptyName
        case tooLong(max: Int)
        case duplicate(String)
        case notFound

        public var description: String {
            switch self {
            case .emptyName: return "Нужно название"
            case .tooLong(let max): return "Название длиннее \(max) символов"
            case .duplicate(let name): return "Пресет «\(name)» уже есть"
            case .notFound: return "Пресет не найден"
            }
        }
    }

    public static let maxNameLength = 32
    public static let currentVersion = 1

    public private(set) var presets: [CustomPreset]

    public init(presets: [CustomPreset] = []) {
        self.presets = presets
    }

    /// Проверка названия: не пустое, не длинное, не повторяет встроенный или другой свой пресет.
    public func validate(name raw: String, excluding id: UUID? = nil) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.emptyName }
        guard name.count <= Self.maxNameLength else { throw ValidationError.tooLong(max: Self.maxNameLength) }
        let key = name.lowercased()
        if PrintPreset.allCases.contains(where: { $0.title.lowercased() == key }) {
            throw ValidationError.duplicate(name)
        }
        if presets.contains(where: { $0.id != id && $0.name.lowercased() == key }) {
            throw ValidationError.duplicate(name)
        }
        return name
    }

    @discardableResult
    public mutating func add(name: String, symbol: String = CustomPreset.defaultSymbol,
                             settings: PrintSettings) throws -> CustomPreset {
        let clean = try validate(name: name)
        let preset = CustomPreset(name: clean, symbol: symbol, settings: settings)
        presets.append(preset)
        return preset
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw ValidationError.notFound }
        presets[index].name = try validate(name: name, excluding: id)
    }

    public mutating func setSymbol(_ id: UUID, _ symbol: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw ValidationError.notFound }
        presets[index].symbol = symbol
    }

    /// Перезаписать настройки пресета текущими.
    public mutating func update(_ id: UUID, settings: PrintSettings) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw ValidationError.notFound }
        presets[index].settings = CustomPreset.normalized(settings)
    }

    public mutating func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { presets[$0] }
        var rest = presets.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        presets = rest
    }

    public func preset(_ id: UUID) -> CustomPreset? {
        presets.first { $0.id == id }
    }

    /// Какой свой пресет совпадает с текущими настройками.
    public func matching(_ settings: PrintSettings) -> CustomPreset? {
        presets.first { $0.matches(settings) }
    }

    // MARK: JSON

    private struct Envelope: Codable {
        var version: Int
        var presets: [CustomPreset]
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(version: Self.currentVersion, presets: presets))
    }

    /// Чтение файла. Битые записи пропускаются, чтобы один сломанный пресет не убил все.
    public static func decode(_ data: Data) throws -> PresetLibrary {
        struct LooseEnvelope: Decodable {
            var version: Int?
            var presets: [Loose]
        }
        struct Loose: Decodable {
            var value: CustomPreset?
            init(from decoder: Decoder) throws {
                value = try? CustomPreset(from: decoder)
            }
        }
        let envelope = try JSONDecoder().decode(LooseEnvelope.self, from: data)
        var seen = Set<UUID>()
        let presets = envelope.presets.compactMap(\.value).filter { seen.insert($0.id).inserted }
        return PresetLibrary(presets: presets)
    }
}
