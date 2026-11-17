import AppKit
import PDFKit
import OttiskCore

// Всё тяжёлое с PDF (поиск белых полей, раскладка, рендер листов, миниатюры) идёт здесь,
// вне главного потока, — окно не подвисает, пока крутишь настройки или листаешь большой файл.
// PDFKit-объекты из окна между потоками не делим: каждый фоновый проход открывает свою копию PDF.

/// Флаг отмены, который можно проверять из фонового потока.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Откуда брать PDF для фоновой работы: файл на диске или данные в памяти.
/// Сравнение — только по ключу (данные большие, сравнивать их незачем).
enum PDFSource: Equatable, @unchecked Sendable {
    case file(URL, key: String)
    case data(Data, key: String)

    var key: String {
        switch self {
        case .file(_, let key), .data(_, let key): return key
        }
    }

    static func == (a: PDFSource, b: PDFSource) -> Bool { a.key == b.key }

    /// Своя копия документа PDFKit — только для потока, который её открыл.
    func openPDF() -> PDFDocument? {
        switch self {
        case .file(let url, _): return PDFDocument(url: url)
        case .data(let data, _): return PDFDocument(data: data)
        }
    }

    func openCG() -> CGPDFDocument? {
        let doc: CGPDFDocument?
        switch self {
        case .file(let url, _): doc = CGPDFDocument(url as CFURL)
        case .data(let data, _): doc = CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) }
        }
        if let doc, !doc.isUnlocked { _ = doc.unlockWithPassword("") }
        return doc
    }
}

/// Кеш непустых областей страниц (для «обрезать белые поля»): страница сканируется один раз на документ.
final class ContentBoxCache: @unchecked Sendable {
    enum Entry { case empty, content(LayoutRect) }

    static let shared = ContentBoxCache()
    private let lock = NSLock()
    private var entries: [String: [Int: Entry]] = [:]

    func get(_ key: String, page: Int) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]?[page]
    }

    func set(_ key: String, page: Int, _ entry: Entry) {
        lock.lock(); entries[key, default: [:]][page] = entry; lock.unlock()
    }

    func forget(_ key: String) {
        lock.lock(); entries[key] = nil; lock.unlock()
    }
}

/// Раскладка + рендер итогового PDF (тот же код для превью и для печати).
enum LayoutJob {
    struct Input: @unchecked Sendable {
        var source: PDFSource
        var pages: [Int]
        var settings: PrintSettings
        var watermark: Watermark
        var headerText: String?
        var rasterDPI: Double
    }

    struct Output: @unchecked Sendable {
        let plan: LayoutPlan
        let data: Data
    }

    enum JobError: LocalizedError {
        case unreadable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "Не получилось открыть файл для превью.")
            case .cancelled: return nil
            }
        }
    }

    /// Синхронно, в текущем (фоновом) потоке.
    static func run(_ input: Input, cancel: CancelFlag) throws -> Output {
        guard let pdf = input.source.openPDF() else { throw JobError.unreadable }
        let s = input.settings
        var boxes: [Int: LayoutRect] = [:]
        if s.trimWhite || (s.marginsActive && !s.marginsAdd) {
            var found: [Int: LayoutRect] = [:]
            var sizes: [Int: LayoutSize] = [:]
            for n in Set(input.pages) {
                if cancel.isCancelled { throw JobError.cancelled }
                guard let page = pdf.page(at: n - 1) else { continue }
                sizes[n] = LayoutRenderer.orientedSize(page)
                let entry: ContentBoxCache.Entry
                if let cached = ContentBoxCache.shared.get(input.source.key, page: n) {
                    entry = cached
                } else {
                    entry = LayoutRenderer.rawContentBox(page).map { ContentBoxCache.Entry.content($0) } ?? ContentBoxCache.Entry.empty
                    ContentBoxCache.shared.set(input.source.key, page: n, entry)
                }
                if case .content(let box) = entry { found[n] = box }
            }
            boxes = ContentBounds.unified(found, sizes: sizes)
        }
        let layoutSource = LayoutRenderer.source(for: pdf, boxes: boxes, headerText: input.headerText)
        let slots = LogicalPages.sequence(selected: input.pages, settings: s)
        let plan = LayoutPlanner.plan(slots: slots, source: layoutSource, settings: s,
                                      sheet: LayoutSize.sheet(forMedia: s.mediaSize))
        if cancel.isCancelled { throw JobError.cancelled }
        let data = try LayoutRenderer.render(plan, from: pdf, settings: s, watermark: input.watermark,
                                             rasterDPI: input.rasterDPI, cancel: cancel)
        return Output(plan: plan, data: data)
    }

    /// В фоне; отмена задачи Swift останавливает рендер между листами.
    static func runInBackground(_ input: Input) async throws -> Output {
        let flag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try run(input, cancel: flag)
            }.value
        } onCancel: {
            flag.cancel()
        }
    }
}

/// Миниатюры страниц: рисуются по одной в фоновой очереди и кешируются.
enum Thumbnails {
    private static let queue = DispatchQueue(label: "ottisk.thumbnails", qos: .userInitiated)
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()
    /// Открытые документы (доступ только из `queue`).
    nonisolated(unsafe) private static var documents: [(key: String, doc: CGPDFDocument)] = []

    private static func cacheKey(_ source: PDFSource, _ index: Int, _ pixels: CGSize, _ box: CGPDFBox) -> NSString {
        "\(source.key)#\(index)@\(Int(pixels.width))x\(Int(pixels.height))/\(box.rawValue)" as NSString
    }

    /// Уже готовая миниатюра (без ожидания).
    static func cached(_ source: PDFSource, index: Int, pixels: CGSize, box: CGPDFBox = .cropBox) -> NSImage? {
        cache.object(forKey: cacheKey(source, index, pixels, box))
    }

    /// Миниатюра страницы `index` (с 0), вписанная в `pixels` (в пикселях).
    static func image(_ source: PDFSource, index: Int, pixels: CGSize, box: CGPDFBox = .cropBox) async -> NSImage? {
        let key = cacheKey(source, index, pixels, box)
        if let hit = cache.object(forKey: key) { return hit }
        let flag = CancelFlag()
        let image: NSImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                queue.async {
                    // Ячейку уже прокрутили мимо — не тратим время.
                    if flag.isCancelled { continuation.resume(returning: nil); return }
                    continuation.resume(returning: render(source, index: index, pixels: pixels, box: box))
                }
            }
        } onCancel: {
            flag.cancel()
        }
        if let image {
            cache.setObject(image, forKey: key, cost: Int(pixels.width * pixels.height * 4))
        }
        return image
    }

    private static func document(_ source: PDFSource) -> CGPDFDocument? {
        if let hit = documents.first(where: { $0.key == source.key }) { return hit.doc }
        guard let doc = source.openCG() else { return nil }
        documents.append((key: source.key, doc: doc))
        if documents.count > 6 { documents.removeFirst() }
        return doc
    }

    private static func render(_ source: PDFSource, index: Int, pixels: CGSize, box: CGPDFBox) -> NSImage? {
        guard pixels.width >= 1, pixels.height >= 1,
              let doc = document(source), let page = doc.page(at: index + 1) else { return nil }
        let rect = page.getBoxRect(box)
        let sideways = page.rotationAngle % 180 != 0
        let pw = sideways ? rect.height : rect.width
        let ph = sideways ? rect.width : rect.height
        guard pw > 0, ph > 0 else { return nil }
        let k = min(pixels.width / pw, pixels.height / ph)
        let w = max(Int((pw * k).rounded()), 1), h = max(Int((ph * k).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(w) / pw, y: CGFloat(h) / ph)
        // Без масштаба: только поворот (/Rotate) и сдвиг в начало координат.
        ctx.concatenate(page.getDrawingTransform(box, rect: CGRect(x: 0, y: 0, width: pw, height: ph),
                                                 rotate: 0, preserveAspectRatio: true))
        ctx.clip(to: rect)
        ctx.drawPDFPage(page)
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }
}
