import AppKit
import SwiftUI
import OttiskCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.reverseBacks) private var reverseBacks = true
    @AppStorage(Prefs.rotateBacks) private var rotateBacks = false
    @AppStorage(Prefs.showMenuBarExtra) private var showMenuBarExtra = true
    @AppStorage(Prefs.defaultPreset) private var defaultPreset = PrintPreset.normal.rawValue
    @AppStorage(Prefs.refreshSeconds) private var refreshSeconds = 3.0
    @AppStorage(Prefs.notifyOnFinish) private var notifyOnFinish = true
    @AppStorage(Prefs.bookletRotateBacks) private var bookletRotateBacks = true

    var body: some View {
        Form {
            Section("Двусторонняя печать вручную") {
                Toggle("Вторую сторону печатать с последнего листа", isOn: $reverseBacks)
                Text("Для MF3010 обычно нужно включить: листы выходят лицом вниз, и пачку можно положить обратно, не перекладывая.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Поворачивать оборот на 180°", isOn: $rotateBacks)
                Text("Включи, если после теста цифра 2 оказалась вверх ногами относительно 1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Брошюра") {
                Toggle("Поворачивать оборот брошюры на 180°", isOn: $bookletRotateBacks)
                Text("Брошюру листают по короткому краю, а пачку в MF3010 переворачивают по длинному — поэтому по умолчанию включено. Проверь на 4 страницах (TESTING.md).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Finder и Shortcuts") {
                Text("Правый клик по файлу → Службы → «Печать через Оттиск».")
                Text("Терминал: open -a Ottisk файл.pdf")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("Ссылка: ottisk://print?file=/путь/к/файлу.pdf&preset=economy")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("Ссылка только открывает файл в Оттиске, печать — по кнопке.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Общее") {
                Toggle("Уведомлять, когда задание напечатано", isOn: $notifyOnFinish)
                Picker("Пресет при запуске", selection: $defaultPreset) {
                    ForEach(PrintPreset.allCases) { preset in
                        Text(preset.title.loc).tag(preset.rawValue)
                    }
                    if !model.presetLibrary.presets.isEmpty {
                        Divider()
                        ForEach(model.presetLibrary.presets) { preset in
                            Text(preset.name).tag(Prefs.customPresetPrefix + preset.id.uuidString)
                        }
                    }
                }
                Toggle("Значок в строке меню", isOn: $showMenuBarExtra)
                Picker("Обновлять состояние", selection: $refreshSeconds) {
                    Text("каждые 2 с").tag(2.0)
                    Text("каждые 3 с").tag(3.0)
                    Text("каждые 10 с").tag(10.0)
                }
            }
            Section("О приложении") {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Text("Оттиск печатает через CUPS — ту же систему, что и сама macOS. Драйвер принтера остаётся родной.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
