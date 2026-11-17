import Foundation
import OttiskCore

/// История печати в ~/Library/Application Support/Ottisk/history.json.
enum HistoryStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Ottisk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? HistoryLog.decode(data)) ?? []
    }

    static func save(_ entries: [HistoryEntry]) {
        guard let data = try? HistoryLog.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
