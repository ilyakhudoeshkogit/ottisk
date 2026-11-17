import AppKit
import OttiskCore

/// Открытие файлов перетаскиванием на иконку в Dock / «Открыть с помощью».
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TempFiles.cleanUp()
        AppModel.shared.start()
        Notifier.shared.setUp()
        ServiceProvider.shared.register()
    }

    /// Файлы (Dock, «Открыть с помощью», `open -a Ottisk файл.pdf`) и ссылки `ottisk://`.
    func application(_ application: NSApplication, open urls: [URL]) {
        let links = urls.filter { $0.scheme?.lowercased() == OttiskLink.scheme }
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { AppModel.shared.add(urls: files) }
        for link in links { AppModel.shared.handle(link: link) }
        MainWindow.bringToFront()
    }

    /// Окно можно закрыть — приложение остаётся в строке меню.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum MainWindow {
    @MainActor
    static func bringToFront() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
