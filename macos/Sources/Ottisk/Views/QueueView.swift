import AppKit
import SwiftUI
import OttiskCore

struct QueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                ContentUnavailableView {
                    Label("Очередь пуста", systemImage: "tray")
                } description: {
                    Text("Здесь будут задания, которые ждут печати. Их можно отменить.")
                }
            } else {
                List {
                    ForEach(model.jobs) { job in
                        JobRow(job: job)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Очередь")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    Task { await model.cancelAll() }
                } label: {
                    Label("Отменить все", systemImage: "xmark.circle")
                }
                .disabled(model.jobs.isEmpty)
                .help("Отменить все задания")
            }
            ToolbarItem {
                Button { Task { await model.refreshAll() } } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct JobRow: View {
    @Environment(AppModel.self) private var model
    let job: PrintJob

    var body: some View {
        HStack(spacing: 12) {
            if job.isActive {
                ProgressView().controlSize(.small)
                    .frame(width: 20)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(for: job))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.cancel(job) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Отменить задание")
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        var parts: [String] = [job.isActive ? "Печатается" : "Ждёт", job.printer.replacingOccurrences(of: "_", with: " ")]
        if let size = job.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}
