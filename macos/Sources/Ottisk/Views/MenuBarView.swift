import AppKit
import SwiftUI
import OttiskCore

/// Быстрый доступ из строки меню: состояние принтера и очередь.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "printer")
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.selectedPrinter?.displayName ?? "Принтер не выбран")
                        .font(.headline)
                    if let printer = model.selectedPrinter {
                        HStack(spacing: 5) {
                            StatusDot(condition: printer.condition)
                            Text(printer.condition.title.loc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if model.selectedPrinter?.condition == .paused {
                    Button("Возобновить") { Task { await model.resumeSelectedPrinter() } }
                        .controlSize(.small)
                }
            }

            Divider()

            if model.jobs.isEmpty {
                Text("Очередь пуста")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.jobs.prefix(6)) { job in
                    HStack {
                        if job.isActive { ProgressView().controlSize(.mini) }
                        Text(model.title(for: job))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            Task { await model.cancel(job) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Отменить")
                    }
                    .font(.callout)
                }
                if model.jobs.count > 6 {
                    Text("и ещё \(model.jobs.count - 6)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Отменить все", role: .destructive) { Task { await model.cancelAll() } }
                    .controlSize(.small)
            }

            Divider()

            HStack {
                Button("Открыть Оттиск") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .task { model.start() }
    }
}
