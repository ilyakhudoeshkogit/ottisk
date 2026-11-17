import Foundation

/// Запись истории печати.
public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var fileName: String
    public var filePath: String
    public var printer: String
    public var pageCount: Int
    public var copies: Int
    public var presetTitle: String
    public var jobIDs: [String]

    public init(id: UUID = UUID(), date: Date = Date(), fileName: String, filePath: String, printer: String,
                pageCount: Int, copies: Int, presetTitle: String, jobIDs: [String]) {
        self.id = id
        self.date = date
        self.fileName = fileName
        self.filePath = filePath
        self.printer = printer
        self.pageCount = pageCount
        self.copies = copies
        self.presetTitle = presetTitle
        self.jobIDs = jobIDs
    }
}

public enum HistoryLog {
    public static let defaultLimit = 100

    /// Новая запись — первой, длина ограничена.
    public static func appending(_ entry: HistoryEntry, to entries: [HistoryEntry], limit: Int = defaultLimit) -> [HistoryEntry] {
        Array(([entry] + entries).prefix(max(limit, 1)))
    }

    public static func encode(_ entries: [HistoryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    public static func decode(_ data: Data) throws -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryEntry].self, from: data)
    }

    /// Сколько листов напечатано за всё время (для маленькой статистики).
    public static func totalPages(_ entries: [HistoryEntry]) -> Int {
        entries.reduce(0) { $0 + $1.pageCount * max($1.copies, 1) }
    }
}

/// Тип файла по расширению: что умеем печатать и как.
public enum DocumentKind: String, Sendable, Equatable {
    case pdf
    case image
    case plainText
    case richText      // rtf, rtfd, docx, doc, odt, html — через NSAttributedString
    case unsupported

    public static func from(pathExtension ext: String) -> DocumentKind {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp": return .image
        case "txt", "text", "md", "markdown", "log", "csv", "json", "xml", "swift", "ts", "js", "cs", "py", "yml", "yaml": return .plainText
        case "rtf", "rtfd", "docx", "doc", "odt", "html", "htm", "webarchive": return .richText
        default: return .unsupported
        }
    }

    public var title: String {
        switch self {
        case .pdf: return "PDF"
        case .image: return "Изображение"
        case .plainText: return "Текст"
        case .richText: return "Документ"
        case .unsupported: return "Не поддерживается"
        }
    }
}
