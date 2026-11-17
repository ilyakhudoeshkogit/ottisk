import AppKit
import ImageIO
import PDFKit
import OttiskCore

/// A4 в пунктах (без привязки к главному потоку — нужен и фоновой конвертации картинок).
private let a4Points = CGSize(width: 595.28, height: 841.89)

/// Превращает любой поддерживаемый файл в PDF, который можно показать и отправить в `lp`.
@MainActor
enum DocumentLoader {
    enum LoadError: LocalizedError {
        case unsupported(String)
        case unreadable(String)
        case locked(String)
        case conversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name):
                return "«\(name)»: такой формат пока не печатаю. Сохрани его в PDF (Файл → Экспорт в PDF)."
            case .unreadable(let name): return "Не получилось открыть «\(name)»."
            case .locked(let name): return "«\(name)» защищён паролем — открой его в Просмотре и сохрани без пароля."
            case .conversionFailed(let name): return "Не получилось подготовить «\(name)» к печати."
            }
        }
    }

    /// A4 в пунктах.
    static let a4 = a4Points

    static func load(_ url: URL) throws -> PrintDocument {
        let name = url.lastPathComponent
        let kind = DocumentKind.from(pathExtension: url.pathExtension)
        switch kind {
        case .pdf:
            guard let pdf = PDFDocument(url: url) else { throw LoadError.unreadable(name) }
            if pdf.isLocked { throw LoadError.locked(name) }
            return PrintDocument(sourceURL: url, kind: kind, pdf: pdf, printableURL: url)
        case .image:
            let out = try imageToPDF(url)
            guard let pdf = PDFDocument(url: out) else { throw LoadError.conversionFailed(name) }
            return PrintDocument(sourceURL: url, kind: kind, pdf: pdf, printableURL: out)
        case .plainText, .richText:
            let out = try textToPDF(url, kind: kind)
            guard let pdf = PDFDocument(url: out) else { throw LoadError.conversionFailed(name) }
            return PrintDocument(sourceURL: url, kind: kind, pdf: pdf, printableURL: out)
        case .unsupported:
            throw LoadError.unsupported(name)
        }
    }

    nonisolated static func isImage(_ url: URL) -> Bool {
        DocumentKind.from(pathExtension: url.pathExtension) == .image
    }

    /// Документ из картинки, уже сконвертированной в PDF (`imageToPDF` в фоне).
    static func wrapConverted(_ url: URL, pdfURL: URL) throws -> PrintDocument {
        guard let pdf = PDFDocument(url: pdfURL) else { throw LoadError.conversionFailed(url.lastPathComponent) }
        return PrintDocument(sourceURL: url, kind: .image, pdf: pdf, printableURL: pdfURL)
    }

    // MARK: Картинки → A4 с полями, вписать с сохранением пропорций

    /// Не трогает интерфейс — можно вызывать из фоновой задачи.
    nonisolated static func imageToPDF(_ url: URL) throws -> URL {
        let name = url.lastPathComponent
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw LoadError.unreadable(name)
        }
        let out = TempFiles.newPDFURL((name as NSString).deletingPathExtension)
        // Скан с DPI в файле (обычно 150–600) и меньше листа: страница = реальный размер картинки.
        // Тогда «100 %» (пресет «Скан паспорта») печатает документ в натуральную величину.
        if let physical = physicalSize(url, pixels: CGSize(width: cgImage.width, height: cgImage.height)) {
            var box = CGRect(origin: .zero, size: physical)
            guard let context = CGContext(out as CFURL, mediaBox: &box, nil) else {
                throw LoadError.conversionFailed(name)
            }
            context.beginPDFPage(nil)
            context.interpolationQuality = .high
            context.draw(cgImage, in: box)
            context.endPDFPage()
            context.closePDF()
            return out
        }
        let landscape = cgImage.width > cgImage.height
        let pageSize = landscape ? CGSize(width: a4Points.height, height: a4Points.width) : a4Points
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(out as CFURL, mediaBox: &mediaBox, nil) else {
            throw LoadError.conversionFailed(name)
        }
        let margin: CGFloat = 24
        let area = mediaBox.insetBy(dx: margin, dy: margin)
        let scale = min(area.width / CGFloat(cgImage.width), area.height / CGFloat(cgImage.height))
        let size = CGSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
        let rect = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                          width: size.width, height: size.height)
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(cgImage, in: rect)
        context.endPDFPage()
        context.closePDF()
        return out
    }

    /// Размер в пунктах по DPI из файла, если DPI правдоподобный (≥ 100) и картинка помещается на A4.
    /// У фото с телефона DPI обычно 72 — тогда nil и картинка просто вписывается в лист.
    nonisolated static func physicalSize(_ url: URL, pixels: CGSize) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let dpiX = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
              let dpiY = (props[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue,
              dpiX >= 100, dpiY >= 100 else { return nil }
        let size = CGSize(width: pixels.width / dpiX * 72, height: pixels.height / dpiY * 72)
        let fitsPortrait = size.width <= a4Points.width && size.height <= a4Points.height
        let fitsLandscape = size.width <= a4Points.height && size.height <= a4Points.width
        return (fitsPortrait || fitsLandscape) ? size : nil
    }

    // MARK: Текст и документы (txt, rtf, docx, doc, odt, html) → PDF через систему печати macOS

    static func textToPDF(_ url: URL, kind: DocumentKind) throws -> URL {
        let name = url.lastPathComponent
        let attributed: NSAttributedString
        do {
            attributed = try readAttributed(url, kind: kind)
        } catch {
            throw LoadError.unreadable(name)
        }
        let out = TempFiles.newPDFURL((name as NSString).deletingPathExtension)

        let printInfo = NSPrintInfo(dictionary: [
            NSPrintInfo.AttributeKey.jobDisposition: NSPrintInfo.JobDisposition.save,
            NSPrintInfo.AttributeKey.jobSavingURL: out,
        ])
        printInfo.paperSize = a4
        printInfo.topMargin = 48
        printInfo.bottomMargin = 48
        printInfo.leftMargin = 56   // чуть шире слева — как поле для подшивки
        printInfo.rightMargin = 40
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let width = a4.width - printInfo.leftMargin - printInfo.rightMargin
        let height = a4.height - printInfo.topMargin - printInfo.bottomMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attributed)
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: out.path) else {
            throw LoadError.conversionFailed(name)
        }
        return out
    }

    private static func readAttributed(_ url: URL, kind: DocumentKind) throws -> NSAttributedString {
        if kind == .plainText {
            let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .windowsCP1251))
                ?? ""
            let isCode = ["swift", "ts", "js", "cs", "py", "json", "xml", "yml", "yaml", "log", "csv"]
                .contains(url.pathExtension.lowercased())
            let font = isCode ? NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
                              : NSFont.systemFont(ofSize: 11)
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch url.pathExtension.lowercased() {
        case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        case "html", "htm":
            options[.documentType] = NSAttributedString.DocumentType.html
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        case "webarchive": options[.documentType] = NSAttributedString.DocumentType.webArchive
        default: break
        }
        return try NSAttributedString(url: url, options: options, documentAttributes: nil)
    }
}

