import AppKit
import PDFKit
import OttiskCore

/// Собирает новые PDF из страниц документа: лицевые/оборотные стороны, тестовый лист.
@MainActor
enum PDFComposer {
    enum ComposeError: LocalizedError {
        case writeFailed
        var errorDescription: String? { "Не получилось сохранить временный PDF." }
    }

    /// PDF из ячеек плана. Пустые ячейки — чистые страницы того же размера.
    static func write(slots: [PageSlot], from source: PDFDocument, rotate180: Bool, hint: String) throws -> URL {
        let result = PDFDocument()
        let fallbackSize = source.page(at: 0)?.bounds(for: .mediaBox).size ?? DocumentLoader.a4
        for slot in slots {
            let page: PDFPage?
            switch slot {
            case .page(let number):
                page = source.page(at: number - 1)?.copy() as? PDFPage
            case .blank:
                page = blankPage(size: fallbackSize)
            }
            guard let page else { continue }
            if rotate180 { page.rotation = (page.rotation + 180) % 360 }
            result.insert(page, at: result.pageCount)
        }
        let url = TempFiles.newPDFURL(hint)
        guard result.write(to: url) else { throw ComposeError.writeFailed }
        return url
    }

    static func blankPage(size: CGSize) -> PDFPage? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }

    /// Двухстраничный тест: понять, как класть пачку для второй стороны.
    static func duplexTestDocument() throws -> URL {
        let url = TempFiles.newPDFURL("duplex-test")
        var box = CGRect(origin: .zero, size: DocumentLoader.a4)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ComposeError.writeFailed }
        let pages: [(String, String)] = [
            ("1", "ЛИЦЕВАЯ СТОРОНА"),
            ("2", "ОБОРОТ"),
        ]
        for (number, title) in pages {
            ctx.beginPDFPage(nil)
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns

            // Рамка в духе ЕСКД: поле 20 мм слева, 5 мм с остальных сторон.
            let mm: CGFloat = 72 / 25.4
            let frame = CGRect(x: 20 * mm, y: 5 * mm, width: box.width - 25 * mm, height: box.height - 10 * mm)
            NSColor.black.setStroke()
            let path = NSBezierPath(rect: frame)
            path.lineWidth = 1.2
            path.stroke()

            let arrow: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 120, weight: .bold)]
            let big: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 220, weight: .bold)]
            let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .semibold)]
            let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]

            func center(_ s: String, _ attrs: [NSAttributedString.Key: Any], y: CGFloat) {
                let str = NSAttributedString(string: s, attributes: attrs)
                let size = str.size()
                str.draw(at: CGPoint(x: frame.midX - size.width / 2, y: y))
            }
            center("↑", arrow, y: frame.maxY - 170)
            center("ВЕРХ", label, y: frame.maxY - 205)
            center(number, big, y: frame.midY - 110)
            center(title, label, y: frame.midY - 160)
            center("Оттиск · тест двусторонней печати", small, y: frame.minY + 24)
            if number == "2" {
                center("Цифры 1 и 2 на одном листе, стрелки смотрят в одну сторону — всё настроено.", small, y: frame.minY + 60)
                center("Стрелки в разные стороны — включи «Поворачивать оборот на 180°» в настройках.", small, y: frame.minY + 42)
            }
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }
}
