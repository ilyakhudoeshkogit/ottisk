import AppKit
import Observation
import PDFKit
import OttiskCore

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // Документы
    var documents: [PrintDocument] = []
    var sidebarSelection: SidebarItem?
    var currentPageIndex = 0

    // Принтеры
    var printers: [Printer] = []
    var selectedPrinterName: String?
    var printerOptions: [PrinterOption] = []
    var driver = ResolvedDriverOptions()

    // Настройки задания
    var settings = PrintSettings()

    // Очередь и история
    var jobs: [PrintJob] = []
    var history: [HistoryEntry] = []
    /// Названия наших заданий по ID — `lpstat -o` их не показывает.
    var jobTitles: [String: String] = [:]

    // Состояние интерфейса
    var isPrinting = false
    var isLoadingPrinters = false
    var errorMessage: String?
    var toast: String?
    var duplexStage: DuplexStage?
    /// Очередь нескольких документов (v0.5): порядок, свои копии/диапазоны, склейка.
    var queue = PrintQueue()
    /// Последний оборот отправлен (true) или отменён (false) — очередь понимает, продолжать ли.
    @ObservationIgnored var lastDuplexCompleted = false
    var showImporter = false

    // Свои пресеты и водяной знак (v0.2)
    var presetLibrary = PresetStore.load()
    var watermark = Watermark(text: "")

    // Живое превью (v0.4): тот же PDF, что уйдёт в печать.
    var previewMode: PreviewMode = .result
    var previewPlan: LayoutPlan?
    /// Собранный PDF превью (рисуется миниатюрами в фоне).
    var previewSource: PDFSource?
    /// Для какого документа собрано превью — чужое не показываем.
    var previewDocumentID: UUID?
    var previewPageIndex = 0
    var previewError: String?
    /// Превью пересобирается в фоне (маленький индикатор, окно не замирает).
    var isRenderingPreview = false
    @ObservationIgnored private var previewGeneration = 0
    /// Сколько файлов сейчас готовится (картинки конвертируются в фоне).
    var loadingDocuments = 0
    @ObservationIgnored private var lastBadge: String?
    @ObservationIgnored private var statusTick = 0

    @ObservationIgnored private var tracker = JobCompletionTracker()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init() {
        Prefs.registerDefaults()
        history = HistoryStore.load()
        let defaultKey = UserDefaults.standard.string(forKey: Prefs.defaultPreset) ?? ""
        if let preset = PrintPreset(rawValue: defaultKey) {
            settings = preset.apply(to: settings)
        } else if defaultKey.hasPrefix(Prefs.customPresetPrefix),
                  let id = UUID(uuidString: String(defaultKey.dropFirst(Prefs.customPresetPrefix.count))),
                  let custom = presetLibrary.preset(id) {
            settings = custom.apply(to: settings)
        }
    }

    // MARK: Производные

    var currentDocument: PrintDocument? {
        if case .document(let id) = sidebarSelection {
            return documents.first { $0.id == id }
        }
        return nil
    }

    var selectedPrinter: Printer? {
        printers.first { $0.name == selectedPrinterName }
    }

    var activeJobs: [PrintJob] { jobs }

    /// Выбранные страницы или текст ошибки диапазона.
    var pageSelection: Result<[Int], PageRange.ParseError>? {
        guard let doc = currentDocument else { return nil }
        do {
            return .success(try PageRange.parse(settings.pageRange, pageCount: doc.pageCount))
        } catch let error as PageRange.ParseError {
            return .failure(error)
        } catch {
            return .failure(.empty)
        }
    }

    var selectedPages: [Int] {
        if case .success(let pages) = pageSelection { return pages }
        return []
    }

    var rangeError: String? {
        if case .failure(let error) = pageSelection { return error.description }
        return nil
    }

    var canPrint: Bool {
        currentDocument != nil && selectedPrinter != nil && !selectedPages.isEmpty && !isPrinting && duplexStage == nil
    }

    var canPrintAll: Bool {
        queue.canStart && selectedPrinter != nil && !isPrinting && duplexStage == nil
    }

    var activePreset: PrintPreset? { PrintPreset.matching(settings) }

    /// Свой пресет, если настройки совпадают с ним (и не совпадают со встроенным).
    var activeCustomPreset: CustomPreset? {
        activePreset == nil ? presetLibrary.matching(settings) : nil
    }

    var activePresetTitle: String {
        activePreset?.title ?? activeCustomPreset?.name ?? String(localized: "Свои настройки")
    }

    var bookletPlan: BookletPlan? {
        guard settings.booklet, !selectedPages.isEmpty else { return nil }
        return BookletPlanner.plan(pages: selectedPages, reverseBacks: UserDefaults.standard.bool(forKey: Prefs.reverseBacks))
    }

    var duplexPlan: DuplexPlan? {
        guard settings.manualDuplex, !settings.booklet, !selectedPages.isEmpty else { return nil }
        return DuplexPlanner.plan(pages: selectedPages, pagesPerSheet: settings.pagesPerSheet,
                                  reverseBacks: UserDefaults.standard.bool(forKey: Prefs.reverseBacks),
                                  copies: settings.copies)
    }

    // MARK: Раскладка и превью

    /// Монохромный принтер (MF3010 — да): превью показываем в оттенках серого.
    var isMonoPrinter: Bool {
        guard let color = printerOptions.first(where: { $0.key == "ColorModel" }) else { return true }
        return !color.choices.contains { c in
            let l = c.lowercased()
            return l.contains("rgb") || l.contains("cmyk") || l.contains("color")
        }
    }

    func headerText(for doc: PrintDocument) -> String {
        doc.name + " · " + Date().formatted(date: .numeric, time: .omitted)
    }

    /// Откуда фоновые задачи читают PDF документа: файл на диске, а если его уже нет — копия из памяти.
    func pdfSource(for doc: PrintDocument) -> PDFSource {
        if FileManager.default.isReadableFile(atPath: doc.printableURL.path) {
            return .file(doc.printableURL, key: doc.id.uuidString)
        }
        return .data(doc.pdf.dataRepresentation() ?? Data(), key: doc.id.uuidString)
    }

    private func layoutInput(doc: PrintDocument, pages: [Int], settings s: PrintSettings, dpi: Double) -> LayoutJob.Input {
        LayoutJob.Input(source: pdfSource(for: doc), pages: pages, settings: s, watermark: watermark,
                        headerText: headerText(for: doc), rasterDPI: dpi)
    }

    /// Пересобрать превью «Как напечатается» (вызывается с задержкой после изменений).
    /// Раскладка и рендер идут в фоне; устаревший проход отменяется, его результат выбрасывается.
    func refreshPreview() async {
        guard let doc = currentDocument, !selectedPages.isEmpty else {
            previewPlan = nil
            previewSource = nil
            previewDocumentID = nil
            return
        }
        previewGeneration &+= 1
        let generation = previewGeneration
        isRenderingPreview = true
        defer { if generation == previewGeneration { isRenderingPreview = false } }
        let input = layoutInput(doc: doc, pages: selectedPages, settings: settings, dpi: 110)
        do {
            let output = try await LayoutJob.runInBackground(input)
            guard generation == previewGeneration, !Task.isCancelled else { return }
            previewSource = .data(output.data, key: "preview-" + UUID().uuidString)
            previewPlan = output.plan
            previewDocumentID = doc.id
            previewError = nil
            if previewPageIndex >= output.plan.sides.count { previewPageIndex = max(output.plan.sides.count - 1, 0) }
        } catch LayoutJob.JobError.cancelled {
            return
        } catch {
            guard generation == previewGeneration, !Task.isCancelled else { return }
            previewError = error.localizedDescription
        }
    }

    /// Листов бумаги на всё задание (для штампа).
    var plannedSheetCount: Int {
        let copies = max(settings.copies, 1)
        if let plan = previewPlan, currentDocument != nil {
            var sheets = plan.sheetCount(twoSided: settings.manualDuplex || settings.booklet) * copies
            if settings.blankBetweenCopies && !settings.manualDuplex && !settings.booklet { sheets += copies - 1 }
            return sheets
        }
        return settings.sheetCount(selectedPages: selectedPages.count) * copies
    }

    /// Команда `lp`, которая уйдёт (для «Подробнее»).
    var commandPreview: String? {
        guard let doc = currentDocument, let printer = selectedPrinterName else { return nil }
        if settings.needsComposition && !settings.booklet && !settings.manualDuplex {
            var s = settings
            if s.blankBetweenCopies { s.copies = 1 }
            let args = LPArgumentsBuilder.arguments(printer: printer, settings: s, driver: driver, title: doc.name,
                                                    pages: nil, files: ["<собранный PDF>.pdf"], composed: true)
            return LPArgumentsBuilder.shellPreview(args)
        }
        if settings.booklet {
            let args = LPArgumentsBuilder.arguments(printer: printer, settings: bookletPassSettings(), driver: driver,
                                                    title: doc.name + " (брошюра)", pages: nil,
                                                    files: ["<брошюра, лицевые>.pdf"], composed: true)
            return LPArgumentsBuilder.shellPreview(args)
        }
        if settings.manualDuplex {
            var s = settings
            s.manualDuplex = false
            s.copies = 1
            s.reverseOrder = false
            let args = LPArgumentsBuilder.arguments(printer: printer, settings: s, driver: driver,
                                                    title: doc.name + " (лицевые)", pages: nil,
                                                    files: ["<лицевые стороны>.pdf"], composed: s.needsComposition)
            return LPArgumentsBuilder.shellPreview(args)
        }
        let file = PageRange.isAll(selectedPages, pageCount: doc.pageCount)
            ? doc.printableURL.path : "<выбранные страницы>.pdf"
        let args = LPArgumentsBuilder.arguments(printer: printer, settings: settings, driver: driver,
                                                title: doc.name, pages: nil, files: [file])
        return LPArgumentsBuilder.shellPreview(args)
    }

    // MARK: Жизненный цикл

    func start() {
        guard !started else { return }
        started = true
        pollTask = Task { [weak self] in
            await self?.refreshAll()
            self?.restorePendingDuplex()
            while !Task.isCancelled {
                let seconds = max(UserDefaults.standard.double(forKey: Prefs.refreshSeconds), 1.5)
                // Когда печатать нечего, опрашиваем CUPS реже — меньше процессов lpstat в фоне.
                let idle = self.map { $0.jobs.isEmpty && $0.duplexStage == nil && !$0.isPrinting } ?? true
                try? await Task.sleep(for: .seconds(idle ? max(seconds * 2, 5) : seconds))
                await self?.refreshStatus()
            }
        }
    }

    func refreshAll() async {
        isLoadingPrinters = true
        defer { isLoadingPrinters = false }
        do {
            printers = try await CUPSClient.printers()
            if selectedPrinterName == nil || selectedPrinter == nil {
                let remembered = UserDefaults.standard.string(forKey: Prefs.lastPrinter)
                selectedPrinterName = printers.first { $0.name == remembered }?.name
                    ?? printers.first { $0.looksLikeMF3010 }?.name
                    ?? printers.first { $0.isDefault }?.name
                    ?? printers.first?.name
            }
            await loadOptions()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshJobs()
    }

    /// Лёгкое обновление по таймеру.
    func refreshStatus() async {
        statusTick &+= 1
        // Полный список принтеров (lpoptions на каждый) — раз в три тика или когда что-то печатается;
        // задания — каждый тик.
        let busy = !jobs.isEmpty || duplexStage != nil || isPrinting
        if busy || statusTick % 3 == 0, let fresh = try? await CUPSClient.printers() {
            if fresh.map(\.name) != printers.map(\.name) {
                printers = fresh
                if selectedPrinter == nil { selectedPrinterName = fresh.first?.name }
            } else if fresh != printers {
                printers = fresh
            }
        }
        await refreshJobs()
    }

    func refreshJobs() async {
        if let fresh = try? await CUPSClient.jobs() {
            if fresh != jobs { jobs = fresh }
            for finished in tracker.update(with: fresh) {
                notifyFinished(finished)
            }
            // Окно второй стороны ждёт, пока первое задание уйдёт из очереди.
            if var stage = duplexStage, var gate = stage.gate {
                gate.update(queue: fresh)
                if gate != stage.gate {
                    stage.gate = gate
                    duplexStage = stage
                }
            }
        }
        let badge = jobs.isEmpty ? nil : "\(jobs.count)"
        if badge != lastBadge {
            lastBadge = badge
            NSApp?.dockTile.badgeLabel = badge
        }
    }

    func printerSelectionChanged() {
        if let name = selectedPrinterName {
            UserDefaults.standard.set(name, forKey: Prefs.lastPrinter)
        }
        Task { await loadOptions() }
    }

    func loadOptions() async {
        guard let name = selectedPrinterName else {
            printerOptions = []
            driver = .init()
            return
        }
        let options = (try? await CUPSClient.options(for: name)) ?? []
        guard selectedPrinterName == name else { return }
        printerOptions = options
        driver = DriverOptionMatcher.resolve(options)
    }

    var mediaOption: PrinterOption? { DriverOptionMatcher.mediaOption(in: printerOptions) }

    // MARK: Документы

    /// Добавить файлы. Возвращается сразу: картинки конвертируются в PDF в фоне, окно не замирает.
    func add(urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { await addInBackground(urls) }
    }

    func addInBackground(_ urls: [URL]) async {
        loadingDocuments += urls.count
        var failures: [String] = []
        var lastID: UUID?
        for url in urls {
            defer { loadingDocuments -= 1 }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let doc: PrintDocument
                if DocumentLoader.isImage(url) {
                    let out = try await Task.detached(priority: .userInitiated) {
                        try DocumentLoader.imageToPDF(url)
                    }.value
                    doc = try DocumentLoader.wrapConverted(url, pdfURL: out)
                } else {
                    doc = try DocumentLoader.load(url)
                }
                documents.append(doc)
                lastID = doc.id
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        syncQueue()
        if let lastID {
            sidebarSelection = .document(lastID)
            currentPageIndex = 0
            settings.pageRange = ""
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    /// «Печать из буфера обмена»: файлы, PDF, картинка, RTF или текст → документ в списке.
    func addFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            add(urls: urls)
            return
        }
        let base = String(localized: "Буфер обмена") + " " + Date().formatted(date: .omitted, time: .standard)
            .replacingOccurrences(of: ":", with: "-")
        func save(_ data: Data, ext: String) {
            let url = TempFiles.directory.appendingPathComponent(base + "." + ext)
            do {
                try data.write(to: url, options: .atomic)
                add(urls: [url])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if let pdf = pb.data(forType: .pdf) {
            save(pdf, ext: "pdf")
        } else if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation {
            save(tiff, ext: "tiff")
        } else if let rtf = pb.data(forType: .rtf) {
            save(rtf, ext: "rtf")
        } else if let text = pb.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            save(Data(text.utf8), ext: "txt")
        } else {
            errorMessage = String(localized: "В буфере обмена нет ни файлов, ни текста, ни картинки.")
        }
    }

    func remove(_ id: UUID) {
        guard !queue.isRunning else { return }
        documents.removeAll { $0.id == id }
        ContentBoxCache.shared.forget(id.uuidString)
        syncQueue()
        if case .document(let selected) = sidebarSelection, selected == id {
            sidebarSelection = documents.last.map { .document($0.id) }
        }
    }

    /// Порядок документов слева = порядок печати очереди.
    func moveDocuments(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !queue.isRunning else { return }
        documents.move(fromOffsets: source, toOffset: destination)
        syncQueue()
    }

    private func syncQueue() {
        queue.sync(with: documents.map { QueueDocumentInfo(id: $0.id, name: $0.name, pageCount: $0.pageCount) })
    }

    func apply(_ preset: PrintPreset) {
        settings = preset.apply(to: settings)
    }

    // MARK: Свои пресеты

    func apply(_ preset: CustomPreset) {
        settings = preset.apply(to: settings)
    }

    /// Сохраняет текущие настройки как новый пресет. Ошибка — текст для поля ввода.
    func saveCurrentAsPreset(name: String, symbol: String) -> String? {
        do {
            try presetLibrary.add(name: name, symbol: symbol, settings: settings)
            PresetStore.save(presetLibrary)
            showToast(String(localized: "Пресет сохранён"))
            return nil
        } catch {
            return (error as? PresetLibrary.ValidationError)?.description ?? error.localizedDescription
        }
    }

    func renamePreset(_ id: UUID, to name: String) -> String? {
        do {
            try presetLibrary.rename(id, to: name)
            PresetStore.save(presetLibrary)
            return nil
        } catch {
            return (error as? PresetLibrary.ValidationError)?.description ?? error.localizedDescription
        }
    }

    func setPresetSymbol(_ id: UUID, _ symbol: String) {
        try? presetLibrary.setSymbol(id, symbol)
        PresetStore.save(presetLibrary)
    }

    func updatePresetWithCurrent(_ id: UUID) {
        try? presetLibrary.update(id, settings: settings)
        PresetStore.save(presetLibrary)
        showToast(String(localized: "Пресет обновлён"))
    }

    func deletePreset(_ id: UUID) {
        presetLibrary.delete(id)
        PresetStore.save(presetLibrary)
    }

    func movePresets(fromOffsets source: IndexSet, toOffset destination: Int) {
        presetLibrary.move(fromOffsets: source, toOffset: destination)
        PresetStore.save(presetLibrary)
    }

    /// Пресет по имени из ссылки ottisk:// («economy», «Черновик» или имя своего пресета).
    func applyPreset(named name: String) {
        let key = name.lowercased()
        if let builtIn = PrintPreset.allCases.first(where: { $0.rawValue.lowercased() == key || $0.title.lowercased() == key }) {
            apply(builtIn)
        } else if let custom = presetLibrary.presets.first(where: { $0.name.lowercased() == key }) {
            apply(custom)
        }
    }

    // MARK: Ссылки ottisk://

    func handle(link url: URL) {
        do {
            switch try OttiskLink.parse(url) {
            case .open(let files, let preset):
                let missing = files.filter { !FileManager.default.fileExists(atPath: $0.path) }
                if !missing.isEmpty {
                    errorMessage = String(localized: "Нет такого файла: ") + missing.map(\.path).joined(separator: ", ")
                }
                let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
                add(urls: existing)
                if let preset, !existing.isEmpty { applyPreset(named: preset) }
            }
        } catch {
            errorMessage = String(localized: "Не понял ссылку: ") + url.absoluteString
        }
    }

    // MARK: Уведомления

    private func notifyFinished(_ finished: JobCompletionTracker.Finished) {
        if var stage = duplexStage, stage.frontJobID == finished.jobID {
            stage.gate?.markFinished()
            duplexStage = stage
            Notifier.shared.post(title: String(localized: "Сторона 1 напечатана"),
                                 body: String(localized: "Переверни пачку и нажми «Печатать сторону 2»."))
        } else {
            Notifier.shared.post(title: String(localized: "Напечатано"), body: finished.title)
        }
    }

    private func submit(_ args: [String], title: String) async throws -> String {
        let id = try await CUPSClient.submit(arguments: args)
        jobTitles[id] = title
        tracker.watch(id, title: title)
        return id
    }

    // MARK: Водяной знак

    /// Источник для печати: сам документ или его копия с водяным знаком.
    private func preparedSource(_ doc: PrintDocument) throws -> (pdf: PDFDocument, url: URL) {
        guard watermark.isActive else { return (doc.pdf, doc.printableURL) }
        let result = try Imposer.watermarked(doc.pdf, watermark: watermark)
        return (result.pdf, result.url)
    }

    // MARK: Печать

    func printCurrent() async {
        guard canPrint, let doc = currentDocument, let printer = selectedPrinterName else { return }
        isPrinting = true
        defer { isPrinting = false }
        do {
            try await runPrint(doc: doc, printer: printer, pages: selectedPages)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshJobs()
    }

    /// Один документ теми же путями, что и одиночная печать (LayoutPlanner/LayoutRenderer, print-scaling=none).
    /// Настройки берутся из `settings` — очередь на время отправки подставляет туда настройки документа.
    private func runPrint(doc: PrintDocument, printer: String, pages: [Int]) async throws {
        let presetTitle = activePresetTitle
        if settings.needsComposition {
            // v0.4: раскладку, поля, надписи и порядок собирает сам Оттиск — тот же PDF, что в превью.
            // Раскладка и рендер 300 dpi — в фоне, окно в это время живое.
            let output = try await LayoutJob.runInBackground(layoutInput(doc: doc, pages: pages, settings: settings, dpi: 300))
            let plan = output.plan
            guard !plan.sides.isEmpty else { return }
            let url = TempFiles.newPDFURL("composed")
            try output.data.write(to: url, options: .atomic)
            guard let composedPDF = PDFDocument(url: url) else { throw LayoutRenderer.RenderError.failed }
            let composed = (url: url, pdf: composedPDF)
            if settings.booklet {
                try await startBooklet(doc: doc, composed: composed.pdf, printer: printer, sideCount: plan.sides.count,
                                       pageCount: pages.count, presetTitle: presetTitle)
            } else if settings.manualDuplex {
                let duplex = DuplexPlanner.sidesPlan(sideCount: plan.sides.count,
                                                     reverseBacks: UserDefaults.standard.bool(forKey: Prefs.reverseBacks),
                                                     copies: settings.copies)
                try await startManualDuplex(doc: doc, source: composed.pdf, printer: printer, plan: duplex,
                                            pageCount: pages.count, presetTitle: presetTitle, composed: true)
            } else {
                try await submitComposed(doc: doc, composed: composed, sideCount: plan.sides.count, printer: printer,
                                         pageCount: pages.count, presetTitle: presetTitle)
            }
            return
        }
        let source = try preparedSource(doc)
        if settings.manualDuplex {
            let plan = DuplexPlanner.plan(pages: pages, pagesPerSheet: settings.pagesPerSheet,
                                          reverseBacks: UserDefaults.standard.bool(forKey: Prefs.reverseBacks),
                                          copies: settings.copies)
            try await startManualDuplex(doc: doc, source: source.pdf, printer: printer, plan: plan,
                                        pageCount: pages.count, presetTitle: presetTitle)
        } else {
            try await submitRegular(doc: doc, source: source, printer: printer, pages: pages, presetTitle: presetTitle)
        }
    }

    // MARK: Очередь документов (v0.5)

    /// Печатает все документы по очереди. Для ручной двусторонней ждёт оборота пачки (DuplexGate/окно оборота).
    func printAll() async {
        guard queue.canStart, !isPrinting, duplexStage == nil, let printer = selectedPrinterName else { return }
        queue.start()
        guard queue.isRunning else { return }
        isPrinting = true
        let shared = settings
        defer {
            settings = shared
            isPrinting = false
            queue.finish()
        }
        if queue.mergeIntoOne {
            await printMerged(shared: shared, printer: printer)
        } else {
            await printSequentially(shared: shared, printer: printer)
        }
        await refreshJobs()
        let q = queue
        if q.failedCount == 0 && q.skippedCount == 0 {
            showToast(String(localized: "Очередь напечатана: ") + "\(q.doneCount)")
        } else {
            showToast(String(localized: "Очередь завершена: ") + "\(q.doneCount)/\(q.items.count)")
        }
    }

    private func printSequentially(shared: PrintSettings, printer: String) async {
        loop: while true {
            switch queue.nextStep() {
            case .finished:
                break loop
            case .print(let id):
                guard let item = queue.item(id), let doc = documents.first(where: { $0.id == id }) else {
                    queue.markFailed(id, String(localized: "Документ убран из списка"))
                    continue
                }
                queue.markPrinting(id)
                do {
                    let pages = try item.pages()
                    settings = item.effectiveSettings(shared: shared)
                    defer { settings = shared }
                    try await runPrint(doc: doc, printer: printer, pages: pages)
                    if duplexStage != nil { queue.markAwaitingFlip(id) } else { queue.markDone(id) }
                } catch {
                    queue.markFailed(id, error.localizedDescription)
                }
                await refreshJobs()
            case .waitForFlip(let id):
                if await waitForDuplexEnd() {
                    queue.markDone(id)
                } else {
                    queue.markFailed(id, String(localized: "Оборот отменён"))
                    queue.stop()
                }
            }
        }
    }

    /// Ждёт, пока окно оборота закроется. true — оборот отправлен, false — отменён.
    private func waitForDuplexEnd() async -> Bool {
        lastDuplexCompleted = false
        while duplexStage != nil {
            try? await Task.sleep(for: .milliseconds(400))
        }
        return lastDuplexCompleted
    }

    /// «Склеить в один PDF»: выбранные страницы всех документов → один PDF → одно задание.
    private func printMerged(shared: PrintSettings, printer: String) async {
        let merged = queue.mergedPages()
        let ids = queue.printable.map(\.id)
        for id in ids { queue.markPrinting(id) }
        do {
            let result = PDFDocument()
            for mp in merged {
                guard let page = documents.first(where: { $0.id == mp.itemID })?.pdf.page(at: mp.page - 1)?.copy() as? PDFPage else { continue }
                result.insert(page, at: result.pageCount)
            }
            guard result.pageCount > 0 else { throw PDFComposer.ComposeError.writeFailed }
            let folder = TempFiles.directory.appendingPathComponent(String(UUID().uuidString.prefix(8)), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = String(localized: "Склеено: ") + PagesWord.format(result.pageCount) + ".pdf"
            let url = folder.appendingPathComponent(name)
            guard result.write(to: url), let pdf = PDFDocument(url: url) else { throw PDFComposer.ComposeError.writeFailed }
            let doc = PrintDocument(sourceURL: url, kind: .pdf, pdf: pdf, printableURL: url)
            settings = PrintQueue.mergedSettings(shared: shared)
            defer { settings = shared }
            try await runPrint(doc: doc, printer: printer, pages: Array(1...pdf.pageCount))
            settings = shared
            if duplexStage != nil {
                if await waitForDuplexEnd() {
                    for id in ids { queue.markDone(id) }
                } else {
                    for id in ids { queue.markFailed(id, String(localized: "Оборот отменён")) }
                }
            } else {
                for id in ids { queue.markDone(id) }
            }
        } catch {
            for id in ids { queue.markFailed(id, error.localizedDescription) }
            errorMessage = error.localizedDescription
        }
    }

    func stopQueue() {
        queue.stop()
    }

    private func submitRegular(doc: PrintDocument, source: (pdf: PDFDocument, url: URL), printer: String,
                               pages: [Int], presetTitle: String) async throws {
        // Диапазон режем ДО number-up: в CUPS -P относится к выходным листам,
        // а человек выбирает исходные страницы. Иначе 5-8 + 2 на листе даёт не то.
        let printableURL: URL
        if PageRange.isAll(pages, pageCount: doc.pageCount) {
            printableURL = source.url
        } else {
            printableURL = try PDFComposer.write(slots: pages.map { .page($0) }, from: source.pdf,
                                                 rotate180: false, hint: "selected")
        }
        let args = LPArgumentsBuilder.arguments(printer: printer, settings: settings, driver: driver,
                                                title: doc.name, pages: nil, files: [printableURL.path])
        let jobID = try await submit(args, title: doc.name)
        record(doc: doc, printer: printer, pages: pages.count, preset: presetTitle, jobIDs: [jobID])
        showToast("Отправлено: \(doc.name)")
    }

    /// Собранный PDF одной стороной. Копии — через CUPS, кроме «пустой лист между копиями».
    private func submitComposed(doc: PrintDocument, composed: (url: URL, pdf: PDFDocument), sideCount: Int,
                                printer: String, pageCount: Int, presetTitle: String) async throws {
        var s = settings
        var url = composed.url
        let copies = max(settings.copies, 1)
        if settings.blankBetweenCopies && copies > 1 {
            var slots: [PageSlot] = []
            for copy in 0..<copies {
                slots += (1...sideCount).map { PageSlot.page($0) }
                if copy < copies - 1 { slots.append(.blank) }
            }
            url = try PDFComposer.write(slots: slots, from: composed.pdf, rotate180: false, hint: "copies")
            s.copies = 1
        }
        let args = LPArgumentsBuilder.arguments(printer: printer, settings: s, driver: driver,
                                                title: doc.name, pages: nil, files: [url.path], composed: true)
        let jobID = try await submit(args, title: doc.name)
        record(doc: doc, printer: printer, pages: pageCount, preset: presetTitle, jobIDs: [jobID])
        showToast(String(localized: "Отправлено: ") + doc.name)
    }

    private func startManualDuplex(doc: PrintDocument, source: PDFDocument, printer: String, plan: DuplexPlan,
                                   pageCount: Int, presetTitle: String, composed: Bool = false) async throws {
        var s = settings
        s.manualDuplex = false
        s.copies = 1            // копии уже разложены в плане
        s.reverseOrder = false  // порядок тоже задан планом
        let submittedDriver = driver
        let rotateBacks = UserDefaults.standard.bool(forKey: Prefs.rotateBacks)
        let backsURL: URL? = plan.needsSecondPass
            ? try PDFComposer.write(slots: plan.backs, from: source, rotate180: rotateBacks, hint: "backs")
            : nil
        let frontsURL = try PDFComposer.write(slots: plan.fronts, from: source, rotate180: false, hint: "fronts")
        let frontArgs = LPArgumentsBuilder.arguments(printer: printer, settings: s, driver: driver,
                                                     title: doc.name + " — сторона 1", pages: nil, files: [frontsURL.path],
                                                     composed: composed)
        let frontID = try await submit(frontArgs, title: doc.name + " — сторона 1")
        let historyID = record(doc: doc, printer: printer, pages: pageCount, preset: presetTitle, jobIDs: [frontID])

        guard plan.needsSecondPass else {
            showToast("Отправлено: \(doc.name)")
            return
        }
        guard let backsURL else { return }
        var stage = DuplexStage(documentName: doc.name, printer: printer, backsURL: backsURL,
                                sheetCount: plan.sheetCount, frontJobID: frontID, historyID: historyID,
                                settings: s, driver: submittedDriver, composed: composed)
        stage.backsRotated = rotateBacks
        beginDuplexStage(stage)
    }

    /// Вторая сторона после переворота пачки.
    func printBacks() async {
        guard var stage = duplexStage, !stage.isPrintingBacks else { return }
        stage.isPrintingBacks = true
        duplexStage = stage
        // «Перевернулось неправильно»: галочку переключили уже после первого прохода — поворачиваем оборот сейчас.
        var backsURL = stage.backsURL
        let wantRotated = UserDefaults.standard.bool(forKey: stage.rotateKey)
        if let baked = stage.backsRotated, baked != wantRotated, let backs = PDFDocument(url: backsURL),
           let rotated = try? PDFComposer.write(slots: (0..<backs.pageCount).map { .page($0 + 1) }, from: backs,
                                                rotate180: true, hint: "backs-rotated") {
            backsURL = rotated
        }
        let args = LPArgumentsBuilder.arguments(printer: stage.printer, settings: stage.settings, driver: stage.driver,
                                                title: stage.documentName + " — сторона 2", pages: nil,
                                                files: [backsURL.path],
                                                composed: stage.composed || stage.settings.needsComposition)
        do {
            let backID = try await submit(args, title: stage.documentName + " — сторона 2")
            if let index = history.firstIndex(where: { $0.id == stage.historyID }) {
                history[index].jobIDs.append(backID)
                HistoryStore.save(history)
            }
            lastDuplexCompleted = true
            duplexStage = nil
            PendingDuplexStore.clear()
            showToast("Вторая сторона отправлена")
        } catch {
            stage.isPrintingBacks = false
            duplexStage = stage
            errorMessage = error.localizedDescription
        }
        await refreshJobs()
    }

    /// Очередь CUPS не читается, а листы уже выехали — пользователь подтверждает сам.
    func confirmFrontPrinted() {
        guard var stage = duplexStage else { return }
        var gate = stage.gate ?? DuplexGate(frontJobID: stage.frontJobID)
        gate.markFinished()
        stage.gate = gate
        duplexStage = stage
    }

    func cancelDuplex() {
        lastDuplexCompleted = false
        duplexStage = nil
        PendingDuplexStore.clear()
    }

    /// Новый этап между проходами: сохраняем на диск, чтобы пережить перезапуск.
    private func beginDuplexStage(_ stage: DuplexStage) {
        var stage = stage
        stage.backsURL = PendingDuplexStore.save(stage)
        stage.gate = DuplexGate(frontJobID: stage.frontJobID)
        duplexStage = stage
    }

    /// После запуска: предложить допечатать оборот, если Оттиск закрыли между проходами.
    func restorePendingDuplex() {
        guard duplexStage == nil, let loaded = PendingDuplexStore.load() else { return }
        let (pending, backsURL) = loaded
        let decision = PendingDuplexPolicy.decide(
            pending,
            backsFileExists: FileManager.default.fileExists(atPath: backsURL.path),
            availablePrinters: printers.isEmpty ? nil : printers.map(\.name))
        switch decision {
        case .discardMissingFile, .discardExpired:
            PendingDuplexStore.clear()
        case .offer, .offerPrinterMissing:
            var stage = DuplexStage(documentName: pending.documentName, printer: pending.printer, backsURL: backsURL,
                                    sheetCount: pending.sheetCount, frontJobID: pending.frontJobID,
                                    historyID: pending.historyID, settings: pending.settings,
                                    driver: pending.driver.resolved)
            stage.createdAt = pending.createdAt
            stage.isRestored = true
            stage.printerMissing = decision == .offerPrinterMissing
            stage.gate = DuplexGate(frontJobID: pending.frontJobID)
            stage.composed = pending.settings.needsComposition
            duplexStage = stage
            Task { await refreshJobs() }
        }
    }

    // MARK: Брошюра

    /// Настройки для каждого прохода брошюры: раскладка уже в PDF, CUPS только печатает листы.
    private func bookletPassSettings() -> PrintSettings {
        var s = settings
        s.booklet = false
        s.manualDuplex = false
        s.copies = 1
        s.reverseOrder = false
        s.pagesPerSheet = 1
        s.fitToPage = true
        s.orientation = .auto
        return s
    }

    /// Брошюра: собранный PDF идёт «лицо, оборот, лицо, оборот…», печатаем в два прохода.
    private func startBooklet(doc: PrintDocument, composed: PDFDocument, printer: String, sideCount: Int,
                              pageCount: Int, presetTitle: String) async throws {
        let passes = DuplexPlanner.bookletPasses(sideCount: sideCount,
                                                 reverseBacks: UserDefaults.standard.bool(forKey: Prefs.reverseBacks),
                                                 copies: settings.copies)
        // Брошюру переворачивают по короткому краю, а MF3010 вручную — по длинному,
        // поэтому по умолчанию оборот брошюры поворачивается на 180°. Проверяется тестом из TESTING.md.
        let rotate = UserDefaults.standard.bool(forKey: Prefs.bookletRotateBacks)
        let s = bookletPassSettings()
        let frontsURL = try PDFComposer.write(slots: passes.fronts, from: composed, rotate180: false, hint: "booklet-fronts")
        let backsURL = passes.backs.isEmpty ? nil
            : try PDFComposer.write(slots: passes.backs, from: composed, rotate180: rotate, hint: "booklet-backs")
        let frontArgs = LPArgumentsBuilder.arguments(printer: printer, settings: s, driver: driver,
                                                     title: doc.name + " — брошюра, сторона 1", pages: nil,
                                                     files: [frontsURL.path], composed: true)
        let frontID = try await submit(frontArgs, title: doc.name + " — брошюра, сторона 1")
        let historyID = record(doc: doc, printer: printer, pages: pageCount, preset: presetTitle + " · брошюра",
                               jobIDs: [frontID])
        guard let backsURL else {
            showToast(String(localized: "Отправлено: ") + doc.name)
            return
        }
        var stage = DuplexStage(documentName: doc.name + " (брошюра)", printer: printer, backsURL: backsURL,
                                sheetCount: passes.sheetCount, frontJobID: frontID, historyID: historyID,
                                settings: s, driver: driver, composed: true)
        stage.rotateKey = Prefs.bookletRotateBacks
        stage.backsRotated = rotate
        beginDuplexStage(stage)
    }

    /// Тестовый лист «1 / 2», чтобы понять, как класть пачку.
    func printDuplexTest() async {
        guard let printer = selectedPrinterName, !isPrinting, duplexStage == nil else { return }
        isPrinting = true
        defer { isPrinting = false }
        let originalSettings = settings
        settings = PrintSettings()
        defer { settings = originalSettings }
        do {
            let url = try PDFComposer.duplexTestDocument()
            guard let pdf = PDFDocument(url: url) else { return }
            let doc = PrintDocument(sourceURL: url, kind: .pdf, pdf: pdf, printableURL: url)
            let plan = DuplexPlanner.plan(pages: [1, 2], pagesPerSheet: 1,
                                          reverseBacks: UserDefaults.standard.bool(forKey: Prefs.reverseBacks))
            try await startManualDuplex(doc: doc, source: pdf, printer: printer, plan: plan,
                                        pageCount: 2, presetTitle: "Тест двусторонней")
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshJobs()
    }

    @discardableResult
    private func record(doc: PrintDocument, printer: String, pages: Int, preset: String, jobIDs: [String]) -> UUID {
        let entry = HistoryEntry(fileName: doc.name, filePath: doc.sourceURL.path, printer: printer,
                                 pageCount: pages, copies: settings.copies, presetTitle: preset, jobIDs: jobIDs)
        history = HistoryLog.appending(entry, to: history)
        HistoryStore.save(history)
        return entry.id
    }

    func clearHistory() {
        history = []
        HistoryStore.save(history)
    }

    func reopen(_ entry: HistoryEntry) {
        let url = URL(fileURLWithPath: entry.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Файла «\(entry.fileName)» больше нет по старому пути."
            return
        }
        add(urls: [url])
    }

    // MARK: Очередь

    func cancel(_ job: PrintJob) async {
        tracker.forget(job.id)
        do { try await CUPSClient.cancel(jobID: job.id) } catch { errorMessage = error.localizedDescription }
        await refreshJobs()
    }

    func cancelAll() async {
        let names = Set(jobs.map(\.printer))
        for name in names {
            tracker.forgetAll(printer: name)
            do { try await CUPSClient.cancelAll(printer: name) } catch { errorMessage = error.localizedDescription }
        }
        await refreshJobs()
    }

    func resumeSelectedPrinter() async {
        guard let name = selectedPrinterName else { return }
        do {
            try await CUPSClient.resume(printer: name)
            showToast("Принтер снова принимает задания")
        } catch {
            errorMessage = "Не получилось возобновить: \(error.localizedDescription)\nМожно так: Системные настройки → Принтеры и сканеры → принтер → Открыть очередь → Возобновить."
        }
        await refreshAll()
    }

    func title(for job: PrintJob) -> String {
        jobTitles[job.id] ?? "Задание \(job.number.map(String.init) ?? job.id)"
    }

    // MARK: Мелочи

    func showToast(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if self?.toast == text { self?.toast = nil }
        }
    }
}
