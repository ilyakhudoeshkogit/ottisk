import AppKit
import SwiftUI
import OttiskCore

/// Вкладка «Сканер»: найти сканер, выбрать DPI/формат, сохранить в ~/Documents/Ottisk Scans.
struct ScanView: View {
    @Environment(AppModel.self) private var model
    @LocalState private var scan = ScanModel.shared

    var body: some View {
        @Bindable var scan = scan

        Form {
            Section {
                Label("Не проверено на MF3010. Нужен драйвер сканера Canon для macOS; без него сканер не появится.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Section("Сканер") {
                if scan.scanners.isEmpty {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(scan.status).foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Устройство", selection: Binding(get: { scan.selectedScannerName },
                                                             set: { scan.select($0) })) {
                        ForEach(scan.scanners, id: \.self) { device in
                            Text(device.name ?? "Сканер").tag(device.name)
                        }
                    }
                    LabeledContent("Состояние", value: scan.status)
                }
            }

            Section("Параметры") {
                Picker("Разрешение", selection: $scan.options.dpi) {
                    ForEach(scan.offeredDPI, id: \.self) { dpi in
                        Text("\(dpi) dpi").tag(dpi)
                    }
                }
                let px = scan.options.a4Pixels()
                Text("Лист A4 ≈ \(px.width) × \(px.height) px. Для документов хватает 300 dpi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Цвет", selection: $scan.options.colorMode) {
                    ForEach(ScanOptions.ColorMode.allCases, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                Picker("Формат", selection: $scan.options.format) {
                    ForEach(ScanOptions.Format.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Собирать сканы в один PDF", isOn: $scan.combineIntoOnePDF)
                    .disabled(scan.options.format != .pdf)
                if scan.combineIntoOnePDF && scan.options.format == .pdf {
                    HStack {
                        Text("Страниц в документе: \(scan.combinedPageCount)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Сбросить") { scan.discardCombined() }
                            .disabled(scan.combinedPageCount == 0)
                        Button("Сохранить PDF") { scan.saveCombined() }
                            .disabled(scan.combinedPageCount == 0)
                    }
                    .controlSize(.small)
                }
            }

            Section {
                HStack {
                    Button {
                        scan.scan()
                    } label: {
                        Label(scan.isScanning ? "Сканирую…" : "Сканировать", systemImage: "scanner")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scan.selectedScanner == nil || scan.isScanning)
                    if scan.isScanning {
                        Button("Отмена") { scan.cancel() }
                    }
                    Spacer()
                    Button("Открыть папку") { scan.revealOutputFolder() }
                }
                Text("Сохраняется в ~/Documents/Ottisk Scans")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !scan.lastScans.isEmpty {
                Section("Последние сканы") {
                    ForEach(scan.lastScans, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.viewfinder")
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("В печать") { model.add(urls: [url]) }
                                .controlSize(.small)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Сканер")
        .alert("Сканер", isPresented: Binding(get: { scan.errorMessage != nil },
                                               set: { if !$0 { scan.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { scan.errorMessage = nil }
        } message: {
            Text(scan.errorMessage ?? "")
        }
        .task { scan.start() }
    }
}
