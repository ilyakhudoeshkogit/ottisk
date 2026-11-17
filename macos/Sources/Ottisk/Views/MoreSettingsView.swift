import SwiftUI
import OttiskCore

/// «Ещё»: настройки, которые в системном диалоге печати есть, но спрятаны глубоко
/// (или которых там нет вовсе). Всё, чего не умеет CUPS, Оттиск делает сам в PDF.
struct MoreSettingsSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage("more.margins") private var openMargins = true
    @AppStorage("more.scale") private var openScale = true
    @AppStorage("more.order") private var openOrder = false
    @AppStorage("more.numbers") private var openNumbers = false
    @AppStorage("more.nup") private var openNUp = false
    @AppStorage("more.eskd") private var openESKD = false
    @AppStorage("more.scans") private var openScans = false
    @AppStorage("more.toner") private var openToner = false

    var body: some View {
        @Bindable var model = model
        let s = model.settings

        Section {
            DisclosureGroup(isExpanded: $openMargins) {
                MarginsEditor()
            } label: {
                GroupLabel(title: "Поля и переплёт", summary: marginsSummary(s))
            }

            DisclosureGroup(isExpanded: $openScale) {
                Picker("Масштаб", selection: $model.settings.scaleMode) {
                    ForEach(ScaleMode.allCases, id: \.self) { Text($0.title.loc).tag($0) }
                }
                .pickerStyle(.segmented)
                if s.scaleMode == .custom {
                    Stepper(value: $model.settings.customScale, in: 10...400, step: 5) {
                        HStack {
                            Text("Свой масштаб")
                            Spacer()
                            TextField("%", value: $model.settings.customScale, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 48)
                            Text("%")
                        }
                    }
                }
                Toggle("Обрезать белые поля исходника", isOn: $model.settings.trimWhite)
                Hint("Срезает пустые края у всех страниц одинаково — текст становится крупнее. Удобно для конспектов и сканов.")
            } label: {
                GroupLabel(title: "Масштаб", summary: s.scaleMode == .custom ? "\(s.customScale) %" : s.scaleMode.title.loc)
            }

            DisclosureGroup(isExpanded: $openOrder) {
                Picker("Страницы", selection: $model.settings.parity) {
                    ForEach(PageParity.allCases, id: \.self) { Text($0.title.loc).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("В обратном порядке", isOn: $model.settings.reverseOrder)
                    .disabled(s.manualDuplex || s.booklet)
                Stepper(value: $model.settings.repeatEach, in: 1...8) {
                    LabeledContent("Повторить каждую страницу", value: "× \(s.repeatEach)")
                }
                Hint("× 2 вместе с «2 на листе» — две одинаковые копии на одном листе (билеты, карточки).")
                Stepper(value: $model.settings.blankEvery, in: 0...50) {
                    LabeledContent("Пустой лист после каждых",
                                   value: s.blankEvery == 0 ? String(localized: "нет") : "\(s.blankEvery)")
                }
                Toggle("Пустой лист между копиями", isOn: $model.settings.blankBetweenCopies)
                    .disabled(s.manualDuplex || s.booklet)
            } label: {
                GroupLabel(title: "Какие страницы и порядок", summary: orderSummary(s))
            }

            DisclosureGroup(isExpanded: $openNumbers) {
                Toggle("Нумерация страниц", isOn: $model.settings.numbering.enabled)
                if s.numbering.enabled {
                    Stepper(value: $model.settings.numbering.startAt, in: 0...999) {
                        LabeledContent("Первая страница — номер", value: "\(s.numbering.startAt)")
                    }
                    Stepper(value: $model.settings.numbering.skipFirst, in: 0...20) {
                        LabeledContent("Без номера первые", value: "\(s.numbering.skipFirst)")
                    }
                    Hint("Эти страницы считаются, но номер на них не печатается: титул по ГОСТ 7.32; по СТП БГУИР — ещё реферат и задание.")
                    Picker("Где", selection: $model.settings.numbering.position) {
                        ForEach(NumberPosition.allCases, id: \.self) { Text($0.title.loc).tag($0) }
                    }
                }
                Toggle("Колонтитул: имя файла и дата", isOn: $model.settings.fileHeader)
            } label: {
                GroupLabel(title: "Нумерация и колонтитул",
                           summary: s.numbering.enabled ? s.numbering.position.title.loc : String(localized: "нет"))
            }

            DisclosureGroup(isExpanded: $openNUp) {
                Picker("Порядок", selection: $model.settings.nUpOrder) {
                    ForEach(NUpOrder.allCases, id: \.self) { Text($0.title.loc).tag($0) }
                }
                .disabled(s.pagesPerSheet == 1)
                Toggle("Рамка вокруг каждой страницы", isOn: $model.settings.cellBorders)
                Toggle("Место для заметок (слайды)", isOn: $model.settings.slideNotes)
                Hint("Слайды в столбик слева, справа линейки. Работает при 4 или 6 на листе.")
            } label: {
                GroupLabel(title: "Несколько страниц на листе",
                           summary: s.pagesPerSheet > 1 ? s.nUpOrder.title.loc : String(localized: "выкл."))
            }

            DisclosureGroup(isExpanded: $openESKD) {
                Toggle("Рамка ЕСКД (20/5/5/5 мм)", isOn: $model.settings.eskdFrame)
                Toggle("Основная надпись, форма 2а", isOn: $model.settings.eskdTitleBlock)
                if s.eskdTitleBlock {
                    TextField("Обозначение", text: $model.settings.eskdDesignation, prompt: Text("ГУИР.400201.001 ПЗ"))
                }
                Hint("Рамка рисуется поверх, а содержимое сжимается так, чтобы до рамки было ≥ 3 мм по бокам и ≥ 10 мм сверху и снизу (ГОСТ Р 2.105-2019, п. 5.1.3). Форма 2а — для последующих листов; большой штамп первого листа (форма 2) Оттиск не рисует.")
            } label: {
                GroupLabel(title: "Рамка и штамп ЕСКД",
                           summary: s.eskdFrame || s.eskdTitleBlock ? String(localized: "вкл.") : String(localized: "нет"))
            }

            DisclosureGroup(isExpanded: $openScans) {
                Picker("Толще тонкие линии", selection: $model.settings.thickenLines) {
                    ForEach(ScanEnhance.levels, id: \.self) { Text(level($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Контраст", selection: $model.settings.contrastBoost) {
                    ForEach(ScanEnhance.levels, id: \.self) { Text(level($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                Hint("Для бледных сканов и фото конспектов. Страница печатается картинкой 300 dpi в оттенках серого, текст перестаёт быть векторным.")
            } label: {
                GroupLabel(title: "Для сканов",
                           summary: s.thickenLines + s.contrastBoost > 0 ? String(localized: "вкл.") : String(localized: "нет"))
            }

            DisclosureGroup(isExpanded: $openToner) {
                if let density = model.driver.density {
                    Picker("Плотность тонера", selection: $model.settings.tonerDensity) {
                        Text("Как в драйвере (\(density.defaultLabel))").tag(String?.none)
                        ForEach(density.choices, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } else {
                    Hint("Драйвер этого принтера не сообщает настройку плотности тонера, поэтому её здесь нет. Светлее печатают «Экономия тонера» (если драйвер её даёт) и «Черновик».")
                }
            } label: {
                GroupLabel(title: "Плотность тонера", summary: s.tonerDensity ?? String(localized: "как в драйвере"))
            }
        } header: {
            Text("Ещё")
        } footer: {
            Text("Всё, что здесь включено, видно в превью «Как напечатается» — это тот же PDF, что уйдёт на принтер.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func level(_ n: Int) -> String { n == 0 ? String(localized: "нет") : String(repeating: "●", count: n) }

    private func marginsSummary(_ s: PrintSettings) -> String {
        if s.margins.isZero && s.gutter == 0 { return String(localized: "нет") }
        let m = s.margins
        func f(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
        var text = "\(f(m.left))/\(f(m.right))/\(f(m.top))/\(f(m.bottom))"
        if s.gutter > 0 { text += " +\(f(s.gutter))" }
        return text + " " + String(localized: "мм")
    }

    private func orderSummary(_ s: PrintSettings) -> String {
        var parts: [String] = []
        if s.parity != .all { parts.append(s.parity.title.loc) }
        if s.reverseOrder { parts.append(String(localized: "обратный")) }
        if s.repeatEach > 1 { parts.append("× \(s.repeatEach)") }
        return parts.isEmpty ? String(localized: "все по порядку") : parts.joined(separator: ", ")
    }
}

/// Поля в мм, «заменить/добавить», переплёт, зеркальность.
struct MarginsEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.settings
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                MMField(title: "Слева", value: $model.settings.margins.left)
                MMField(title: "Справа", value: $model.settings.margins.right)
            }
            GridRow {
                MMField(title: "Сверху", value: $model.settings.margins.top)
                MMField(title: "Снизу", value: $model.settings.margins.bottom)
            }
        }
        HStack {
            Button("ГОСТ 30/15/20/20") { model.settings.margins = .gost7_32 }
            Button("Без полей") {
                model.settings.margins = .zero
                model.settings.gutter = 0
            }
        }
        .controlSize(.small)
        Picker("Свои поля файла", selection: $model.settings.marginsAdd) {
            Text("Заменить").tag(false)
            Text("Добавить").tag(true)
        }
        .pickerStyle(.segmented)
        .disabled(!s.marginsActive)
        if s.marginsAdd {
            Hint("Вся страница вместе со своими полями уменьшается и встаёт внутрь новых полей.")
        } else {
            Hint("Белые края файла срезаются, текст ставится ровно в новые поля (крупнее не становится). Слева гарантированно не меньше заданного — хватит под дырокол.")
        }
        MMField(title: "Под переплёт", value: $model.settings.gutter)
        Picker("Переплёт", selection: $model.settings.gutterEdge) {
            ForEach(BindingEdge.allCases, id: \.self) { Text($0.title.loc).tag($0) }
        }
        .pickerStyle(.segmented)
        Toggle("Зеркальные поля на обороте", isOn: $model.settings.mirrorMargins)
            .disabled(!s.manualDuplex)
        Hint("При печати с двух сторон поле переплёта на обороте переезжает на другую сторону, чтобы дырки не попали в текст.")
    }
}

struct MMField: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .frame(minWidth: 52, alignment: .leading)
            TextField("", value: $value, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Stepper("", value: $value, in: 0...80, step: 1)
                .labelsHidden()
            Text("мм").foregroundStyle(.secondary)
        }
    }
}

struct GroupLabel: View {
    let title: LocalizedStringKey
    let summary: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct Hint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
