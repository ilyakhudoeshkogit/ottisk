import AppKit
import CoreImage
import PDFKit
import OttiskCore

/// Рисует `LayoutPlan` в PDF. Один и тот же код делает и превью, и файл для печати,
/// поэтому «Как напечатается» в окне совпадает с тем, что уйдёт в CUPS.
/// Не привязан к главному потоку: вызывается из фоновых задач (`LayoutJob`) со своей копией PDF.
enum LayoutRenderer {
    enum RenderError: LocalizedError {
        case failed
        var errorDescription: String? { String(localized: "Не получилось собрать PDF для печати.") }
    }

    // MARK: Исходник

    /// Размер страницы с учётом поворота (/Rotate) — в тех же координатах, что и раскладка.
    static func orientedSize(_ page: PDFPage) -> LayoutSize {
        let box = page.bounds(for: .cropBox)
        let sideways = page.rotation % 180 != 0
        return LayoutSize(width: Double(sideways ? box.height : box.width),
                          height: Double(sideways ? box.width : box.height))
    }

    /// Непустая область одной страницы (по снимку 72 dpi) или nil для пустой страницы.
    static func rawContentBox(_ page: PDFPage) -> LayoutRect? {
        contentBox(page, size: orientedSize(page))
    }

    private static func contentBox(_ page: PDFPage, size: LayoutSize) -> LayoutRect? {
        let scale = 1.0   // 1 пиксель на пункт — точности 0,35 мм хватает
        let w = max(Int(size.width * scale), 1), h = max(Int(size.height * scale), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let ref = page.pageRef else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(ref.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                                                rotate: 0, preserveAspectRatio: true))
        ctx.clip(to: ref.getBoxRect(.cropBox))
        ctx.drawPDFPage(ref)
        guard let data = ctx.data else { return nil }
        // Буфер CGContext идёт сверху вниз — как и ждёт ContentBounds.
        let buffer = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h)
        guard let px = ContentBounds.detect(gray: Array(buffer), width: w, height: h) else { return nil }
        return ContentBounds.toPage(px, pixelsPerPoint: scale, page: size)
    }

    static func source(for pdf: PDFDocument, boxes: [Int: LayoutRect], headerText: String?) -> LayoutSource {
        let fallback = LayoutSize.a4
        return LayoutSource(
            pageSize: { n in pdf.page(at: n - 1).map(orientedSize) ?? fallback },
            contentBox: { boxes[$0] },
            headerText: headerText)
    }

    // MARK: Рисование

    /// - Parameters:
    ///   - rasterDPI: разрешение для страниц с «усилением сканов» (превью — меньше, печать — 300).
    ///   - cancel: проверяется между листами — устаревшее превью бросаем, не дорисовывая.
    static func render(_ plan: LayoutPlan, from pdf: PDFDocument, settings: PrintSettings,
                       watermark: Watermark, rasterDPI: Double, cancel: CancelFlag? = nil) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw RenderError.failed }
        let enhance = settings.thickenLines > 0 || settings.contrastBoost > 0
        for side in plan.sides {
            if cancel?.isCancelled == true { throw LayoutJob.JobError.cancelled }
            var box = CGRect(x: 0, y: 0, width: side.size.width, height: side.size.height)
            ctx.beginPage(mediaBox: &box)
            for placement in side.placements {
                guard case .page(let number) = placement.slot, let page = pdf.page(at: number - 1) else { continue }
                if enhance {
                    drawEnhanced(page, placement, settings: settings, dpi: rasterDPI, ctx)
                } else {
                    drawVector(page, placement, ctx)
                }
                Imposer.drawWatermark(watermark, in: placement.target.cg.intersection(placement.cell.cg), ctx)
            }
            for line in side.lines { stroke(line, ctx) }
            for label in side.labels { draw(label, ctx) }
            ctx.endPage()
        }
        ctx.closePDF()
        return data as Data
    }

    static func renderToFile(_ plan: LayoutPlan, from pdf: PDFDocument, settings: PrintSettings,
                             watermark: Watermark, hint: String) throws -> (url: URL, pdf: PDFDocument) {
        let data = try render(plan, from: pdf, settings: settings, watermark: watermark, rasterDPI: 300)
        let url = TempFiles.newPDFURL(hint)
        try data.write(to: url, options: .atomic)
        guard let doc = PDFDocument(url: url) else { throw RenderError.failed }
        return (url, doc)
    }

    private static func pageTransform(_ ref: CGPDFPage, size: LayoutSize) -> CGAffineTransform {
        ref.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                                rotate: 0, preserveAspectRatio: true)
    }

    private static func drawVector(_ page: PDFPage, _ p: SidePlacement, _ ctx: CGContext) {
        guard let ref = page.pageRef else { return }
        let size = orientedSize(page)
        ctx.saveGState()
        ctx.clip(to: p.cell.cg)
        ctx.clip(to: p.target.cg)
        ctx.translateBy(x: p.target.x - p.crop.x * p.scale, y: p.target.y - p.crop.y * p.scale)
        ctx.scaleBy(x: p.scale, y: p.scale)
        ctx.concatenate(pageTransform(ref, size: size))
        ctx.clip(to: ref.getBoxRect(.cropBox))
        ctx.drawPDFPage(ref)
        ctx.restoreGState()
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Растр + фильтры: темнее тонкие линии, выше контраст, в оттенках серого.
    private static func drawEnhanced(_ page: PDFPage, _ p: SidePlacement, settings: PrintSettings, dpi: Double, _ ctx: CGContext) {
        guard let ref = page.pageRef, p.crop.width > 0, p.crop.height > 0 else { return }
        let size = orientedSize(page)
        let k = dpi / 72
        let w = max(Int(p.crop.width * k), 1), h = max(Int(p.crop.height * k), 1)
        guard w * h < 60_000_000,
              let bmp = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            drawVector(page, p, ctx)
            return
        }
        bmp.setFillColor(gray: 1, alpha: 1)
        bmp.fill(CGRect(x: 0, y: 0, width: w, height: h))
        bmp.interpolationQuality = .high
        bmp.scaleBy(x: k, y: k)
        bmp.translateBy(x: -p.crop.x, y: -p.crop.y)
        bmp.concatenate(pageTransform(ref, size: size))
        bmp.clip(to: ref.getBoxRect(.cropBox))
        bmp.drawPDFPage(ref)
        guard let raw = bmp.makeImage() else { return }
        var image = CIImage(cgImage: raw)
        let radius = ScanEnhance.thickenRadius(level: settings.thickenLines, dpi: dpi)
        if radius >= 0.5, let f = CIFilter(name: "CIMorphologyMinimum") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(radius, forKey: kCIInputRadiusKey)
            if let out = f.outputImage { image = out.cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }
        }
        if settings.contrastBoost > 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(0, forKey: kCIInputSaturationKey)
            f.setValue(ScanEnhance.contrast(level: settings.contrastBoost), forKey: kCIInputContrastKey)
            if let out = f.outputImage { image = out }
        }
        guard let result = ciContext.createCGImage(image, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return }
        ctx.saveGState()
        ctx.clip(to: p.cell.cg)
        ctx.interpolationQuality = .high
        ctx.draw(result, in: p.target.cg)
        ctx.restoreGState()
    }

    private static func stroke(_ line: LayoutLine, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(gray: 0, alpha: line.width < 0.45 ? 0.45 : 1)
        ctx.setLineWidth(line.width)
        ctx.setLineCap(.square)
        if line.dashed { ctx.setLineDash(phase: 0, lengths: [3, 2]) }
        ctx.move(to: CGPoint(x: line.x1, y: line.y1))
        ctx.addLine(to: CGPoint(x: line.x2, y: line.y2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func font(_ label: SideLabel) -> NSFont {
        if label.monospaced { return NSFont.monospacedDigitSystemFont(ofSize: label.fontSize, weight: .regular) }
        // ГОСТ 7.32-2017 рекомендует Times New Roman — им и ставим номера.
        return NSFont(name: "Times New Roman", size: label.fontSize) ?? NSFont.systemFont(ofSize: label.fontSize)
    }

    private static func draw(_ label: SideLabel, _ ctx: CGContext) {
        let text = NSAttributedString(string: label.text, attributes: [.font: font(label), .foregroundColor: NSColor.black])
        let size = text.size()
        let x: Double
        switch label.alignment {
        case .left: x = label.x
        case .center: x = label.x - size.width / 2
        case .right: x = label.x - size.width
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: CGPoint(x: x, y: label.y - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension LayoutRect {
    var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
