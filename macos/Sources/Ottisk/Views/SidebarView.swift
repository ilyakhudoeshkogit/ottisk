import AppKit
import SwiftUI
import OttiskCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.sidebarSelection) {
            Section("Документы") {
                if model.documents.isEmpty {
                    Text("Пока пусто")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(model.documents) { doc in
                    DocumentRow(document: doc)
                        .tag(SidebarItem.document(doc.id))
                        .contextMenu {
                            Button("Показать в Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([doc.sourceURL])
                            }
                            Button("Убрать из списка", role: .destructive) { model.remove(doc.id) }
                        }
                }
                .onMove { model.moveDocuments(fromOffsets: $0, toOffset: $1) }
                if model.documents.count > 1 {
                    Label {
                        HStack {
                            Text("Печатать все")
                            Spacer()
                            Text("\(model.documents.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Theme.ink.opacity(0.15), in: Capsule())
                        }
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .tag(SidebarItem.batch)
                }
            }
            Section("Принтер") {
                Label {
                    HStack {
                        Text("Очередь")
                        Spacer()
                        if !model.jobs.isEmpty {
                            Text("\(model.jobs.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Theme.ink.opacity(0.15), in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "tray.full")
                }
                .tag(SidebarItem.queue)

                Label("История", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.history)

                Label("Сканер", systemImage: "scanner")
                    .tag(SidebarItem.scan)
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if case .document(let id) = model.sidebarSelection { model.remove(id) }
        }
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }
}

struct DocumentRow: View {
    let document: PrintDocument

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(document.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(document.kind.title.loc) · \(PagesWord.format(document.pageCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: document.symbol)
        }
        .help(document.sourceURL.path)
    }
}

/// Внизу сайдбара: сколько напечатано (маленькая приятная статистика).
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = HistoryLog.totalPages(model.history)
        if total > 0 {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                Text("Отправлено: \(PagesWord.format(total))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// «1 страница», «3 страницы», «5 страниц».
enum PagesWord {
    static func format(_ n: Int) -> String {
        "\(n) \(word(n, "страница", "страницы", "страниц"))"
    }

    static func sheets(_ n: Int) -> String {
        "\(n) \(word(n, "лист", "листа", "листов"))"
    }

    static func word(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = n % 100
        let mod10 = n % 10
        if (11...14).contains(mod100) { return many }
        if mod10 == 1 { return one }
        if (2...4).contains(mod10) { return few }
        return many
    }
}
