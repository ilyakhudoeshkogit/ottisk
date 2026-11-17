import AppKit
import OttiskCore

/// «Печать через Оттиск» в меню Finder → Службы (и в правом клике по файлу).
///
/// Описание службы лежит в Info.plist (NSServices, NSMessage = printWithOttisk).
/// Служба только открывает файлы в Оттиске — печать по-прежнему по кнопке.
@MainActor
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    func register() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc func printWithOttisk(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "Оттиск: в выделении нет файлов" as NSString
            return
        }
        AppModel.shared.add(urls: urls)
        MainWindow.bringToFront()
    }
}
