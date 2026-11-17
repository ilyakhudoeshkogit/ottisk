import Foundation
import OttiskCore

/// Папка ~/Library/Application Support/Ottisk.
enum AppSupport {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Ottisk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Свои пресеты в ~/Library/Application Support/Ottisk/presets.json.
enum PresetStore {
    static var fileURL: URL { AppSupport.directory.appendingPathComponent("presets.json") }

    static func load() -> PresetLibrary {
        guard let data = try? Data(contentsOf: fileURL) else { return PresetLibrary() }
        if let library = try? PresetLibrary.decode(data) { return library }
        // Файл испорчен — откладываем копию, чтобы не потерять, и начинаем с пустого списка.
        let backup = fileURL.deletingPathExtension().appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return PresetLibrary()
    }

    static func save(_ library: PresetLibrary) {
        guard let data = try? library.encode() else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
