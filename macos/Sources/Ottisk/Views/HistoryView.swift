import AppKit
import SwiftUI
import OttiskCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @LocalState private var confirmClear = false

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView {
                    Label("Истории пока нет", systemImage: "clock")
                } description: {
                    Text("Здесь появятся последние печати — их можно повторить в один клик.")
                }
            } else {
                List {
                    Section {
                        ForEach(model.history) { entry in
                            HistoryRow(entry: entry)
                        }
                    } header: {
                        Text("Всего отправлено: \(PagesWord.format(HistoryLog.totalPages(model.history)))")
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("История")
        .toolbar {
            ToolbarItem {
                Button { confirmClear = true } label: {
                    Label("Очистить", systemImage: "trash")
                }
                .disabled(model.history.isEmpty)
            }
        }
        .confirmationDialog("Очистить историю?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { model.clearHistory() }
        }
    }
}

struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .foregroundStyle(Theme.ink)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(PagesWord.format(entry.pageCount)) × \(entry.copies) · \(entry.presetTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Ещё раз") { model.reopen(entry) }
                .controlSize(.small)
                .help("Открыть файл снова и проверить настройки")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.filePath)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Показать в Finder")
        }
        .padding(.vertical, 3)
    }
}
