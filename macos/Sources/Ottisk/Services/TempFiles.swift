import Foundation

/// Временные PDF (сконвертированные документы, лицевые/оборотные стороны).
enum TempFiles {
    static var directory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Ottisk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newPDFURL(_ hint: String) -> URL {
        let safe = hint.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("\(safe)-\(UUID().uuidString.prefix(8)).pdf")
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
