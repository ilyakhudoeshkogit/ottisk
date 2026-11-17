import SwiftUI
import OttiskCore

/// Схема одной стороны листа: страницы — серые блоки с «строками», рамки, номера.
/// Рисуется из того же `LayoutPlan`, что и печать.
struct SideSchematic: View {
    let side: SideLayout
    var showArea = false

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / side.size.width, size.height / side.size.height)
            let w = side.size.width * k, h = side.size.height * k
            let ox = (size.width - w) / 2, oy = (size.height - h) / 2
            func r(_ rect: LayoutRect) -> CGRect {
                CGRect(x: ox + rect.x * k, y: oy + h - (rect.y + rect.height) * k, width: rect.width * k, height: rect.height * k)
            }
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * k, y: oy + h - y * k) }
            let sheet = CGRect(x: ox, y: oy, width: w, height: h)
            ctx.fill(Path(sheet), with: .color(.white))
            ctx.stroke(Path(sheet), with: .color(.black.opacity(0.35)), lineWidth: 0.5)
            if showArea {
                ctx.stroke(Path(r(side.area)), with: .color(Theme.ink.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
            }
            for placement in side.placements {
                guard case .page = placement.slot else { continue }
                let t = r(placement.target.intersection(placement.cell))
                ctx.fill(Path(t), with: .color(.black.opacity(0.06)))
                // «Строки текста».
                let step = max(t.height / 12, 1.6)
                var y = t.minY + step
                while y < t.maxY - step * 0.5 {
                    var line = Path()
                    line.move(to: CGPoint(x: t.minX + t.width * 0.08, y: y))
                    line.addLine(to: CGPoint(x: t.maxX - t.width * 0.08, y: y))
                    ctx.stroke(line, with: .color(.black.opacity(0.45)), lineWidth: max(step * 0.28, 0.4))
                    y += step
                }
            }
            for l in side.lines {
                var path = Path()
                path.move(to: p(l.x1, l.y1))
                path.addLine(to: p(l.x2, l.y2))
                ctx.stroke(path, with: .color(.black.opacity(l.width < 0.45 ? 0.4 : 0.85)),
                           lineWidth: max(l.width * k, 0.5))
            }
            for label in side.labels {
                let fontSize = max(label.fontSize * k, 3)
                let text = Text(label.text).font(.system(size: fontSize)).foregroundColor(.black)
                let anchor: UnitPoint = label.alignment == .left ? .leading : (label.alignment == .right ? .trailing : .center)
                ctx.draw(text, at: p(label.x, label.y), anchor: anchor)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Маленькая схема листа для карточки пресета.
struct PresetSchematic: View {
    let settings: PrintSettings

    private var side: SideLayout? {
        var s = settings
        s.pageRange = ""
        let slides = s.slideNotes
        let pageSize: LayoutSize = slides ? LayoutSize(width: 720, height: 405)
            : (s.scaleMode == .actual && s.contrastBoost > 0 ? LayoutSize(width: Units.pt(125), height: Units.pt(88)) : .a4)
        let text = LayoutRect(x: Units.pt(20), y: Units.pt(20), width: pageSize.width - Units.pt(40), height: pageSize.height - Units.pt(40))
        let source = LayoutSource(pageSize: { _ in pageSize }, contentBox: { _ in slides ? nil : text }, headerText: "file.pdf")
        let count = s.booklet ? 4 : max(LayoutPlanner.perSheetPublic(s), 1) * 2
        let plan = LayoutPlanner.plan(slots: (1...count).map { .page($0) }, source: source, settings: s)
        // Для нумерации показываем вторую страницу, если титул без номера.
        if !s.booklet && s.pagesPerSheet == 1 && plan.sides.count > 1 && s.numbering.enabled { return plan.sides[1] }
        return plan.sides.first
    }

    var body: some View {
        if let side {
            SideSchematic(side: side, showArea: !settings.margins.isZero)
        }
    }
}
