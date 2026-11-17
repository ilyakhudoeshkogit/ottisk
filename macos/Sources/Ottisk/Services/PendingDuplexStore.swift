import Foundation
import OttiskCore

/// Незавершённая двусторонняя печать: ~/Library/Application Support/Ottisk/Pending/.
/// Файл оборота переносится сюда из временной папки, потому что временная
/// папка чистится при каждом запуске.
enum PendingDuplexStore {
    static var directory: URL {
        let dir = AppSupport.directory.appendingPathComponent("Pending", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var fileURL: URL { directory.appendingPathComponent("pending-duplex.json") }

    /// Сохраняет этап и возвращает новый путь к файлу оборота.
    @discardableResult
    static func save(_ stage: DuplexStage) -> URL {
        let fm = FileManager.default
        clearFiles(except: stage.backsURL)
        var backsURL = stage.backsURL
        if backsURL.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL {
            let target = directory.appendingPathComponent(backsURL.lastPathComponent)
            try? fm.removeItem(at: target)
            if (try? fm.moveItem(at: backsURL, to: target)) != nil
                || (try? fm.copyItem(at: backsURL, to: target)) != nil {
                backsURL = target
            }
        }
        let pending = PendingDuplex(documentName: stage.documentName, printer: stage.printer,
                                    backsFileName: backsURL.lastPathComponent, sheetCount: stage.sheetCount,
                                    frontJobID: stage.frontJobID, historyID: stage.historyID,
                                    settings: stage.settings, driver: stage.driver, createdAt: stage.createdAt)
        if let data = try? pending.encode() {
            try? data.write(to: fileURL, options: .atomic)
        }
        return backsURL
    }

    static func load() -> (PendingDuplex, URL)? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let pending = try? PendingDuplex.decode(data) else {
            clear()
            return nil
        }
        return (pending, directory.appendingPathComponent(pending.backsFileName))
    }

    /// Забыть задание и удалить файл оборота.
    static func clear() {
        clearFiles(except: nil)
    }

    private static func clearFiles(except keep: URL?) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.standardizedFileURL != keep?.standardizedFileURL {
            try? fm.removeItem(at: item)
        }
    }
}
