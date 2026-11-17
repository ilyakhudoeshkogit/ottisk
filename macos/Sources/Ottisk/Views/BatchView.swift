import AppKit
import SwiftUI
import OttiskCore

/// «Печатать все»: несколько документов одной очередью (v0.5).
/// Слева порядок и свои копии/диапазон, справа превью выбранного, внизу — склейка и кнопка.
struct BatchView: View {
    @Environment(AppModel.self) private var model
    @LocalState private var selected: UUID?
    @LocalState private var previewPage = 0

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 380, idealWidth: 430)
            preview
                .frame(minWidth: 240)
        }
        .navigationTitle("Печатать все")
        .navigationSubtitle(PagesWord.format(totalPages))
    }

    private var totalPages: Int {
        model.queue.items.reduce(0) { sum, item in sum + ((try? item.pages().count) ?? 0) }
    }

    private var list: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(model.queue.items) { item in
                    BatchRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Убрать из списка", role: .destructive) { model.remove(item.id) }
                                .disabled(model.queue.isRunning)
                        }
                }
                .onMove { model.moveDocuments(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand {
                if let selected { model.remove(selected) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Склеить в один PDF", isOn: $model.queue.mergeIntoOne)
                    .disabled(model.queue.isRunning)
                Group {
                    if model.queue.mergeIntoOne {
                        Text("Одно задание: выбранные страницы всех документов подряд. Удобно для двусторонней печати.")
                    } else {
                        Text("Документы уходят по очереди, у каждого свои копии и диапазон.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Text("Общий пресет: ") + Text(model.activePresetTitle).fontWeight(.semibold)
                    Spacer()
                    if model.queue.isRunning {
                        Button("Остановить") { model.stopQueue() }
                    }
                    Button {
                        Task { await model.printAll() }
                    } label: {
                        Label("Печатать все", systemImage: "printer.dotmatrix")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPrintAll)
                }
                .font(.callout)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let id = selected, let doc = model.documents.first(where: { $0.id == id }) {
            PDFKitView(document: doc.pdf, pageIndex: $previewPage)
                .id(doc.id)
        } else {
            ContentUnavailableView {
                Label("Выбери документ", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Здесь будет его превью.")
            }
        }
    }
}

struct BatchRow: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    private func binding<T>(_ keyPath: WritableKeyPath<QueueItem, T>) -> Binding<T> {
        Binding(get: { item[keyPath: keyPath] },
                set: { value in model.queue.update(item.id) { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        let locked = model.queue.isRunning
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                stateIcon
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(PagesWord.format(item.pageCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Свои копии и страницы", isOn: binding(\.hasOverride))
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(locked)
            if item.hasOverride {
                HStack(spacing: 12) {
                    Stepper(value: binding(\.copies), in: 1...99) {
                        Text("Копии: \(item.copies)")
                            .monospacedDigit()
                    }
                    TextField("Все страницы", text: binding(\.pageRange))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                }
                .font(.caption)
                .disabled(locked)
                if let error = item.rangeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Как общий пресет")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status = statusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .waiting: Image(systemName: "circle").foregroundStyle(.secondary)
        case .printing: ProgressView().controlSize(.small)
        case .awaitingFlip: Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var statusText: String? {
        switch item.state {
        case .waiting: return nil
        case .printing: return String(localized: "Отправляю…")
        case .awaitingFlip: return String(localized: "Жду, пока ты перевернёшь пачку")
        case .done: return String(localized: "Отправлено")
        case .failed(let message): return message
        case .skipped: return String(localized: "Пропущен")
        }
    }

    private var statusColor: Color {
        if case .failed = item.state { return .red }
        if item.state == .awaitingFlip { return .orange }
        return .secondary
    }
}
