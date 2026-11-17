import AppKit
import PDFKit
import OttiskCore

/// Новые PDF «поверх» исходного: брошюра (2 страницы на сторону) и водяной знак.
/// Рисуем через CGPDFPage — так учитывается поворот страниц (/Rotate) и cropBox.
@MainActor
enum Imposer {
    enum ImposeError: LocalizedError {
        case writeFailed
        var errorDescription: String? { String(localized: "Не получилось собрать PDF для печати.") }
    }

    // MARK: Водяной знак

    /// Копия документа с водяным знаком на каждой странице.
    static func watermarked(_ source: PDFDocument, watermark: Watermark) throws -> (url: URL, pdf: PDFDocument) {
        let url = TempFiles.newPDFURL("watermark")
        guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else { throw ImposeError.writeFailed }
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index)?.pageRef else { continue }
            let crop = page.getBoxRect(.cropBox)
            let sideways = page.rotationAngle % 180 != 0
            var box = CGRect(x: 0, y: 0,
                             width: sideways ? crop.height : crop.width,
                             height: sideways ? crop.width : crop.height)
            ctx.beginPage(mediaBox: &box)
            draw(page, in: box, ctx)
            drawWatermark(watermark, in: box, ctx)
            ctx.endPage()
        }
        ctx.closePDF()
        guard let pdf = PDFDocument(url: url) else { throw ImposeError.writeFailed }
        return (url, pdf)
    }

    nonisolated static func drawWatermark(_ watermark: Watermark, in box: CGRect, _ ctx: CGContext) {
        guard watermark.isActive else { return }
        let size = CGFloat(watermark.fontSize(pageWidth: Double(box.width), pageHeight: Double(box.height)))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .heavy),
            .foregroundColor: NSColor(white: 0.2, alpha: CGFloat(watermark.clampedOpacity)),
        ]
        let text = NSAttributedString(string: watermark.trimmedText, attributes: attrs)
        let textSize = text.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.saveGState()
        ctx.translateBy(x: box.midX, y: box.midY)
        ctx.rotate(by: CGFloat(watermark.angle * .pi / 180))
        text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Брошюра

    /// Альбомный A4: на каждой стороне две страницы (A5). Пустые ячейки остаются белыми.
    static func booklet(sides: [BookletSide], from source: PDFDocument, rotate180: Bool, hint: String) throws -> URL {
        let a4 = DocumentLoader.a4
        var sheet = CGRect(x: 0, y: 0, width: a4.height, height: a4.width)
        let url = TempFiles.newPDFURL(hint)
        guard let ctx = CGContext(url as CFURL, mediaBox: &sheet, nil) else { throw ImposeError.writeFailed }
        let margin: CGFloat = 12
        let left = CGRect(x: 0, y: 0, width: sheet.width / 2, height: sheet.height).insetBy(dx: margin, dy: margin)
        let right = left.offsetBy(dx: sheet.width / 2, dy: 0)
        for side in sides {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            if rotate180 {
                ctx.translateBy(x: sheet.width, y: sheet.height)
                ctx.rotate(by: .pi)
            }
            draw(side.left, from: source, in: left, ctx)
            draw(side.right, from: source, in: right, ctx)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    private static func draw(_ slot: PageSlot, from source: PDFDocument, in rect: CGRect, _ ctx: CGContext) {
        guard case .page(let number) = slot, let page = source.page(at: number - 1)?.pageRef else { return }
        draw(page, in: rect, ctx)
    }

    /// Вписать страницу в прямоугольник (только уменьшение, с сохранением пропорций).
    private static func draw(_ page: CGPDFPage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        ctx.clip(to: page.getBoxRect(.cropBox))
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }
}
