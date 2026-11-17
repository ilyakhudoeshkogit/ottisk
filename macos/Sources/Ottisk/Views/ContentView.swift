import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OttiskCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @LocalState private var showInspector = true
    @LocalState private var isDropTargeted = false

    static let importTypes: [UTType] = {
        var types: [UTType] = [.pdf, .image, .plainText, .rtf, .rtfd, .html, .sourceCode, .commaSeparatedText, .json]
        for id in ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc", "org.oasis-open.opendocument.text"] {
            if let t = UTType(id) { types.append(t) }
        }
        return types
    }()

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { if isDropTargeted { DropHighlight() } }
                .overlay(alignment: .bottom) { ToastView() }
                .overlay(alignment: .top) {
                    if model.loadingDocuments > 0 {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Открываю файлы…")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 10)
                    }
                }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .disabled(model.queue.isRunning)
                .inspectorColumnWidth(min: 300, ideal: 330, max: 420)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.add(urls: files)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.showImporter = true } label: {
                    Label("Добавить файлы", systemImage: "plus")
                }
                .help("Открыть файлы (⌘O)")
            }
            ToolbarItem(placement: .principal) {
                PrinterStatusPill()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.sidebarSelection == .batch {
                    Button {
                        Task { await model.printAll() }
                    } label: {
                        Label("Печатать все", systemImage: "printer.dotmatrix")
                    }
                    .disabled(!model.canPrintAll)
                    .help("Печатать все документы по очереди (⌥⌘P)")
                } else {
                    Button {
                        Task { await model.printCurrent() }
                    } label: {
                        Label("Печать", systemImage: "printer")
                    }
                    .disabled(!model.canPrint)
                    .help("Печать (⌘P)")
                }

                Button { showInspector.toggle() } label: {
                    Label("Настройки печати", systemImage: "sidebar.right")
                }
            }
        }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: Self.importTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.add(urls: urls) }
        }
        .sheet(item: $model.duplexStage) { _ in
            DuplexSheet()
                .environment(model)
        }
        .alert("Что-то пошло не так",
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: model.selectedPrinterName) { model.printerSelectionChanged() }
        .onChange(of: model.sidebarSelection) { model.currentPageIndex = 0 }
        .task { model.start() }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebarSelection {
        case .document:
            if let doc = model.currentDocument {
                PreviewView(document: doc)
            } else {
                EmptyDropView()
            }
        case .batch:
            if model.documents.count > 1 {
                BatchView()
            } else {
                EmptyDropView()
            }
        case .queue:
            QueueView()
        case .history:
            HistoryView()
        case .scan:
            ScanView()
        case nil:
            EmptyDropView()
        }
    }
}

/// Подсветка при перетаскивании файлов в окно.
struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background(Theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .padding(12)
            .overlay {
                Label("Отпусти, чтобы добавить", systemImage: "arrow.down.doc")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
            .allowsHitTesting(false)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.snappy, value: model.toast)
        }
    }
}

/// Пустое окно: большая зона для файлов в виде чертёжного листа.
struct EmptyDropView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            SheetFrame()
                .frame(width: 220, height: 300)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Theme.ink)
                        Text("Перетащи файлы сюда")
                            .font(.headline)
                        Text("PDF, картинки, текст, Word")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: -20)
                }
            HStack {
                Button("Выбрать файлы…") { model.showImporter = true }
                Button("Из буфера обмена") { model.addFromClipboard() }
                    .help("Текст, картинка или PDF из буфера обмена (⇧⌘V)")
            }
            .controlSize(.large)
            Text("Можно бросить файл и на иконку в Dock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Лист с рамкой и маленьким штампом — тот самый намёк на ЕСКД.
struct SheetFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.paper)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                Rectangle()
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                    .padding(EdgeInsets(top: h * 0.025, leading: w * 0.09, bottom: h * 0.025, trailing: w * 0.025))
                // Штамп
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Rectangle().fill(Color.primary.opacity(0.45)).frame(height: 0.8)
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: w * 0.55, height: h * 0.13)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.45)).frame(width: 0.8)
                        .padding(.leading, w * 0.18)
                }
                .padding(.trailing, w * 0.025)
                .padding(.bottom, h * 0.025)
            }
        }
    }
}
