import AppKit
import SwiftUI
import OttiskCore

/// Между проходами ручной двусторонней печати.
struct DuplexSheet: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.rotateBacks) private var rotateBacks = false
    @AppStorage(Prefs.bookletRotateBacks) private var bookletRotateBacks = true
    @LocalState private var waitingSince = Date()
    @LocalState private var showMechanics = false

    var body: some View {
        let stage = model.duplexStage
        let ready = stage?.canPrintBacks ?? false

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage?.isRestored == true
                         ? LocalizedStringKey("Незавершённая двусторонняя печать")
                         : LocalizedStringKey("Двусторонняя печать: проход 1 из 2"))
                        .font(.title2.weight(.semibold))
                    Text(stage.map { "\($0.documentName) · \(PagesWord.sheets($0.sheetCount))" } ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let stage, stage.isRestored {
                restoredNote(stage)
            }

            statusRow(stage: stage, ready: ready)

            FlipAnimationView()
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Дождись, пока выпадет последний лист.")
                step(2, "Возьми всю пачку из выходного лотка сверху. Не переворачивай и не перекладывай листы.")
                step(3, "Поверни пачку на столе на 180° — край, который смотрел на тебя, теперь смотрит на принтер.")
                step(4, "Вставь в лоток подачи чистой стороной вверх, этим краем вперёд. Нажми кнопку ниже.")
            }

            DisclosureGroup("Почему так и в чём я не уверен", isExpanded: $showMechanics) {
                Text("MF3010 берёт бумагу из лотка спереди внизу и печатает на верхней стороне листа, а выдаёт лист сверху лицом вниз, верхом страницы к тебе. Поэтому пачку не переворачивают, а только поворачивают: чистая сторона уже сверху. Последний напечатанный лист лежит сверху и уйдёт в принтер первым — Оттиск сам печатает обороты в обратном порядке, а при нечётном числе страниц первым идёт пустой оборот. Не уверен я в одном: каким краем драйвер подаёт верх страницы. Если оборот вышел вверх ногами — включи галочку ниже, это запомнится.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .font(.callout)

            if let stage {
                Toggle(isOn: stage.rotateKey == Prefs.bookletRotateBacks ? $bookletRotateBacks : $rotateBacks) {
                    Text(stage.backsRotated == nil
                         ? LocalizedStringKey("Перевернулось неправильно — повернуть оборот на 180° (со следующего раза)")
                         : LocalizedStringKey("Перевернулось неправильно — повернуть оборот на 180°"))
                }
                .font(.callout)
                .help("Запоминается. Если первый раз не уверен — сначала «Принтер → Тест двусторонней печати» (лист «1 / 2»).")
            }

            HStack {
                Button("Отменить вторую сторону", role: .cancel) { model.cancelDuplex() }
                    .disabled(stage?.isPrintingBacks == true)
                Spacer()
                Button {
                    Task { await model.printBacks() }
                } label: {
                    HStack {
                        if stage?.isPrintingBacks == true { ProgressView().controlSize(.small) }
                        Text("Стопку перевернул — печатать дальше")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(stage?.isPrintingBacks == true || !ready)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled()
        .onAppear { waitingSince = Date() }
    }

    /// Ждём, пока сторона 1 уйдёт из очереди CUPS.
    @ViewBuilder
    private func statusRow(stage: DuplexStage?, ready: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if ready {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Сторона 1 ушла из очереди. Принтер может ещё выталкивать последний лист — дождись его.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Печатается сторона 1 (нечётные страницы)… Кнопка станет активной, когда задание уйдёт из очереди.")
                        .fixedSize(horizontal: false, vertical: true)
                    // Запасной выход, если очередь CUPS не читается.
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        if stage?.gate?.checkedQueue == false, context.date.timeIntervalSince(waitingSince) > 30 {
                            Button("Очередь не отвечает, а листы уже напечатались") { model.confirmFrontPrinted() }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((ready ? Color.green : Theme.ink).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Пояснение для задания, восстановленного после перезапуска.
    private func restoredNote(_ stage: DuplexStage) -> some View {
        let when = PendingDuplexPolicy.whenText(stage.createdAt)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Сторона 1 ушла на принтер \(when), а Оттиск закрылся до второго прохода. Если пачка ещё у тебя, можно допечатать оборот.")
                .fixedSize(horizontal: false, vertical: true)
            if stage.printerMissing {
                Label("Принтера «\(stage.printer)» сейчас нет в списке. Включи его и подключи USB, иначе задание встанет в очередь.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .frame(width: 22, height: 22)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                .foregroundStyle(Theme.ink)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
