import AppKit
import SwiftUI
import OttiskCore

/// Правая панель: принтер, пресеты, страницы, дополнительно, штамп и кнопка «Печать».
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.showCommand) private var showCommand = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Form {
                PrinterSection()

                Section("Пресет") {
                    PresetGrid()
                    CustomPresetsRow()
                }

                Section("Страницы") {
                    Stepper(value: $model.settings.copies, in: 1...99) {
                        HStack {
                            Text("Копии")
                            Spacer()
                            TextField("Копии", value: $model.settings.copies, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 48)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Диапазон", text: $model.settings.pageRange, prompt: Text("Все, например 1-3, 5"))
                        if let error = model.rangeError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Picker("Страниц на листе", selection: $model.settings.pagesPerSheet) {
                        ForEach(PrintSettings.allowedPagesPerSheet, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .disabled(model.settings.booklet)
                    Toggle("С двух сторон (вручную)", isOn: $model.settings.manualDuplex)
                        .disabled(model.settings.booklet)
                    if let plan = model.duplexPlan {
                        DuplexPlanHint(plan: plan)
                    }
                    Toggle("Брошюра (сложить пополам)", isOn: $model.settings.booklet)
                    if let plan = model.bookletPlan {
                        BookletPlanHint(plan: plan)
                    }
                }

                WatermarkSection()

                Section("Дополнительно") {
                    Picker("Ориентация", selection: $model.settings.orientation) {
                        ForEach(PageOrientation.allCases, id: \.self) { o in
                            Text(o.title.loc).tag(o)
                        }
                    }
                    if let media = model.mediaOption {
                        Picker("Бумага", selection: $model.settings.mediaSize) {
                            Text("Как в принтере (\(media.defaultLabel))").tag(String?.none)
                            ForEach(media.choices, id: \.self) { choice in
                                Text(choice).tag(String?.some(choice))
                            }
                        }
                    }
                    Toggle("Экономия тонера", isOn: $model.settings.tonerSave)
                        .disabled(model.driver.tonerSave == nil)
                    if model.driver.tonerSave == nil && model.selectedPrinter != nil {
                        Text("Драйвер принтера не даёт режим экономии. Помогает «Черновик» и 2 страницы на листе.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Черновое качество", isOn: Binding(
                        get: { model.settings.quality == .draft },
                        set: { model.settings.quality = $0 ? .draft : .normal }))
                }

                MoreSettingsSection()

                Section {
                    DisclosureGroup("Команда lp", isExpanded: $showCommand) {
                        Text(model.commandPreview ?? "Выбери документ и принтер")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            VStack(spacing: 10) {
                TitleBlockView()
                PrintButton()
            }
            .padding(12)
            .background(.bar)
        }
    }
}

struct PrintButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.printCurrent() }
        } label: {
            HStack {
                if model.isPrinting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.settings.manualDuplex ? "arrow.triangle.2.circlepath" : "printer.fill")
                }
                Text(model.settings.manualDuplex ? "Печатать сторону 1" : "Печать")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canPrint)
    }
}

struct PrinterSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Section("Принтер") {
            if model.printers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.isLoadingPrinters ? "Ищу принтеры…" : "Принтеров не найдено",
                          systemImage: "printer.dotmatrix")
                    if !model.isLoadingPrinters {
                        Text("Подключи MF3010 по USB и добавь его в системных настройках. Подробности — в README.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Настройки принтеров…") { SystemLinks.openPrinterSettings() }
                            Button("Обновить") { Task { await model.refreshAll() } }
                        }
                    }
                }
            } else {
                Picker("Принтер", selection: $model.selectedPrinterName) {
                    ForEach(model.printers) { printer in
                        Text(printer.displayName + (printer.isDefault ? " (по умолчанию)" : ""))
                            .tag(String?.some(printer.name))
                    }
                }
                if let printer = model.selectedPrinter {
                    HStack(spacing: 8) {
                        StatusDot(condition: printer.condition)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(printer.condition.title.loc)
                            if let message = printer.stateMessage, !message.isEmpty, message != printer.condition.title {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if printer.condition == .paused {
                            Button("Возобновить") { Task { await model.resumeSelectedPrinter() } }
                                .controlSize(.small)
                        }
                    }
                    if printer.condition == .paperOut {
                        Text("Положи бумагу в лоток подачи — задание продолжится само.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct StatusDot: View {
    let condition: PrinterCondition

    var body: some View {
        Circle()
            .fill(Theme.color(for: condition))
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            .accessibilityLabel(condition.title.loc)
    }
}

/// Плашка состояния принтера в тулбаре.
struct PrinterStatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let printer = model.selectedPrinter {
            HStack(spacing: 6) {
                StatusDot(condition: printer.condition)
                Text(printer.displayName)
                    .fontWeight(.medium)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(printer.condition.title.loc)
                    .foregroundStyle(.secondary)
                if !model.jobs.isEmpty {
                    Text("· в очереди \(model.jobs.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        } else {
            Text("Принтер не выбран")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct PresetGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PrintPreset.Group.allCases, id: \.self) { group in
                Text(group.title.loc)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(PrintPreset.presets(in: group)) { preset in
                        PresetButton(preset: preset, isActive: model.activePreset == preset,
                                     schematic: preset.apply(to: model.settings)) {
                            withAnimation(.snappy) { model.apply(preset) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PresetButton: View {
    let preset: PrintPreset
    let isActive: Bool
    /// Настройки после применения пресета — для схемы листа.
    let schematic: PrintSettings
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isActive ? Theme.ink : .secondary)
                    Spacer(minLength: 0)
                    // Схема листа: при наведении или когда пресет выбран.
                    if hovering || isActive {
                        PresetSchematic(settings: schematic)
                            .frame(width: 34, height: 34)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .frame(height: 34, alignment: .top)
                Text(preset.title.loc)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(preset.subtitle.loc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Theme.ink.opacity(0.10) : (hovering ? Color.primary.opacity(0.05) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Theme.ink : Theme.line, lineWidth: isActive ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .help(preset.subtitle.loc)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct DuplexPlanHint: View {
    let plan: DuplexPlan

    private func describe(_ slots: [PageSlot]) -> String {
        let parts = slots.prefix(12).map { slot -> String in
            if case .page(let n) = slot { return "\(n)" }
            return "□"
        }
        return parts.joined(separator: " ") + (slots.count > 12 ? " …" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Проход 1: \(describe(plan.fronts))")
            if plan.needsSecondPass {
                Text("Проход 2: \(describe(plan.backs))")
            }
            Text("\(PagesWord.sheets(plan.sheetCount)) бумаги, □ — пустая страница")
                .foregroundStyle(.secondary)
        }
        .font(.caption.monospaced())
    }
}

/// Подсказка: как разложатся страницы брошюры.
struct BookletPlanHint: View {
    let plan: BookletPlan

    private func text(_ slot: PageSlot) -> String {
        if case .page(let n) = slot { return "\(n)" }
        return "□"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(plan.sheets.prefix(4).enumerated()), id: \.offset) { index, sheet in
                Text("Лист \(index + 1): [\(text(sheet.front.left)) | \(text(sheet.front.right))] / [\(text(sheet.back.left)) | \(text(sheet.back.right))]")
            }
            if plan.sheetCount > 4 {
                Text("…")
            }
            Text("\(PagesWord.sheets(plan.sheetCount)), два прохода; сложи пачку пополам")
                .foregroundStyle(.secondary)
        }
        .font(.caption.monospaced())
    }
}

/// Водяной знак: текст, заметность, быстрые варианты.
struct WatermarkSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Section("Водяной знак") {
            HStack {
                TextField("Текст", text: $model.watermark.text, prompt: Text("Нет"))
                Menu {
                    ForEach(Watermark.suggestions, id: \.self) { word in
                        Button(LocalizedStringKey(word)) { model.watermark.text = NSLocalizedString(word, comment: "Водяной знак") }
                    }
                    Divider()
                    Button("Убрать") { model.watermark.text = "" }
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            if model.watermark.isActive {
                Slider(value: $model.watermark.opacity, in: Watermark.opacityRange) {
                    Text("Заметность")
                }
                Picker("Наклон", selection: $model.watermark.angle) {
                    Text("Прямо").tag(0.0)
                    Text("45°").tag(45.0)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

/// Свои пресеты: кнопки + «Сохранить текущие» + «Управлять».
struct CustomPresetsRow: View {
    @Environment(AppModel.self) private var model
    @LocalState private var showSave = false
    @LocalState private var showManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.presetLibrary.presets.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(model.presetLibrary.presets) { preset in
                        CustomPresetButton(preset: preset, isActive: model.activeCustomPreset?.id == preset.id) {
                            withAnimation(.snappy) { model.apply(preset) }
                        }
                    }
                }
            }
            HStack {
                Button {
                    showSave = true
                } label: {
                    Label("Сохранить как пресет…", systemImage: "plus")
                }
                .popover(isPresented: $showSave, arrowEdge: .bottom) {
                    SavePresetPopover(isPresented: $showSave)
                        .environment(model)
                }
                Spacer()
                if !model.presetLibrary.presets.isEmpty {
                    Button("Управлять…") { showManager = true }
                }
            }
            .controlSize(.small)
        }
        .sheet(isPresented: $showManager) {
            PresetManagerView()
                .environment(model)
        }
    }
}

struct CustomPresetButton: View {
    let preset: CustomPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: preset.symbol)
                    .foregroundStyle(isActive ? Theme.ink : .secondary)
                Text(preset.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(isActive ? Theme.ink.opacity(0.10) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? Theme.ink : Theme.line, style: StrokeStyle(lineWidth: isActive ? 1.5 : 1, dash: isActive ? [] : [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(preset.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct SavePresetPopover: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @LocalState private var name = ""
    @LocalState private var symbol = CustomPreset.defaultSymbol
    @LocalState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Новый пресет")
                .font(.headline)
            Text("Сохранятся все текущие настройки, кроме диапазона страниц.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Название", text: $name, prompt: Text("Например, «Счета»"))
                .onSubmit(save)
            SymbolPicker(selection: $symbol)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Отмена") { isPresented = false }
                Button("Сохранить", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func save() {
        if let message = model.saveCurrentAsPreset(name: name, symbol: symbol) {
            error = message
        } else {
            isPresented = false
        }
    }
}

struct SymbolPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 6), spacing: 4) {
            ForEach(CustomPreset.symbolChoices, id: \.self) { name in
                Button {
                    selection = name
                } label: {
                    Image(systemName: name)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(selection == name ? Theme.ink.opacity(0.18) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Список своих пресетов: переименовать, сменить значок, перезаписать текущими, удалить, перетащить.
struct PresetManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Мои пресеты")
                .font(.title3.weight(.semibold))
            List {
                ForEach(model.presetLibrary.presets) { preset in
                    PresetManagerRow(preset: preset)
                }
                .onMove { model.movePresets(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 220)
            Text("Хранятся в ~/Library/Application Support/Ottisk/presets.json")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 480)
    }
}

struct PresetManagerRow: View {
    @Environment(AppModel.self) private var model
    let preset: CustomPreset
    @LocalState private var name = ""
    @LocalState private var error: String?
    @LocalState private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(CustomPreset.symbolChoices, id: \.self) { symbol in
                    Button {
                        model.setPresetSymbol(preset.id, symbol)
                    } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                Image(systemName: preset.symbol)
            }
            .menuStyle(.button)
                .buttonStyle(.borderless)
            .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                TextField("Название", text: $name)
                    .textFieldStyle(.plain)
                    .onSubmit { error = model.renamePreset(preset.id, to: name) }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Обновить") { model.updatePresetWithCurrent(preset.id) }
                .controlSize(.small)
                .help("Перезаписать текущими настройками")
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Удалить")
        }
        .onAppear { name = preset.name }
        .confirmationDialog("Удалить пресет «\(preset.name)»?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { model.deletePreset(preset.id) }
        }
    }
}
