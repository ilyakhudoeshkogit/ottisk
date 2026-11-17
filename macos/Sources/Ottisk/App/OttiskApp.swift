import SwiftUI
import OttiskCore

@main
struct OttiskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @LocalState private var model = AppModel.shared
    @AppStorage(Prefs.showMenuBarExtra) private var showMenuBarExtra = true

    var body: some Scene {
        Window("Оттиск", id: "main") {
            ContentView()
                .environment(model)
                .tint(Theme.ink)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { OttiskCommands(model: model) }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environment(model)
                .tint(Theme.ink)
        } label: {
            Image(systemName: model.activeJobs.isEmpty ? "printer" : "printer.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.ink)
        }
    }
}

struct OttiskCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Открыть файлы…") { model.showImporter = true }
                .keyboardShortcut("o", modifiers: .command)
            Button("Из буфера обмена") { model.addFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {
            Button("Печать") { Task { await model.printCurrent() } }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!model.canPrint)
            Button("Печатать все документы") { Task { await model.printAll() } }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!model.canPrintAll)
        }
        CommandMenu("Принтер") {
            Button("Обновить состояние") { Task { await model.refreshAll() } }
                .keyboardShortcut("r", modifiers: .command)
            Button("Возобновить принтер") { Task { await model.resumeSelectedPrinter() } }
                .disabled(model.selectedPrinter?.condition != .paused)
            Divider()
            Button("Тест двусторонней печати") { Task { await model.printDuplexTest() } }
                .disabled(model.selectedPrinter == nil)
            Button("Настройки принтеров macOS…") { SystemLinks.openPrinterSettings() }
        }
    }
}
