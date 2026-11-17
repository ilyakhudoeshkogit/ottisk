import Foundation

/// Ссылки `ottisk://print?file=/путь/к/файлу.pdf` (для Shortcuts, Automator, терминала).
///
/// Ссылка только ОТКРЫВАЕТ файлы в окне Оттиска. Сама по себе она ничего не печатает —
/// иначе любая веб-страница могла бы отправить задание на принтер.
public enum OttiskLink {
    public static let scheme = "ottisk"

    public enum Action: Equatable, Sendable {
        /// Открыть файлы и подготовить к печати (выбрать пресет, если указан).
        case open(files: [URL], preset: String?)
    }

    public enum ParseError: Error, Equatable {
        case wrongScheme
        case unknownAction(String)
        case noFiles
        case notAbsolute(String)
    }

    public static func parse(_ url: URL) throws -> Action {
        guard url.scheme?.lowercased() == scheme else { throw ParseError.wrongScheme }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ParseError.noFiles
        }
        // ottisk://print?... → host = print; ottisk:print?... → path = print
        let action = (components.host ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard action == "print" || action == "open" else { throw ParseError.unknownAction(action) }
        var files: [URL] = []
        var preset: String?
        for item in components.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            switch item.name.lowercased() {
            case "file", "path":
                files.append(try fileURL(from: value))
            case "preset":
                preset = value
            default:
                continue
            }
        }
        guard !files.isEmpty else { throw ParseError.noFiles }
        return .open(files: files, preset: preset)
    }

    static func fileURL(from value: String) throws -> URL {
        if value.lowercased().hasPrefix("file://"), let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL
        }
        var path = value
        if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        }
        guard path.hasPrefix("/") else { throw ParseError.notAbsolute(value) }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    /// Собрать ссылку (для подсказки в настройках и README).
    public static func make(files: [String], preset: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "print"
        var items = files.map { URLQueryItem(name: "file", value: $0) }
        if let preset { items.append(URLQueryItem(name: "preset", value: preset)) }
        components.queryItems = items
        return components.url
    }
}
