import SwiftUI

/// Анимированная схема для Canon MF3010 (вид сверху, принтер — сверху картинки).
/// Пачка выходит лицом вниз → её берут, НЕ переворачивая → поворачивают на 180° на столе →
/// вставляют в лоток подачи красным краем (верх страниц) вперёд, чистой стороной вверх.
/// Только фигуры SwiftUI, без картинок.
struct FlipAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let cycle = 10.0

    var body: some View {
        VStack(spacing: 6) {
            if reduceMotion {
                // Без движения: ключевые кадры рядом.
                HStack(spacing: 4) {
                    frame(at: 0.5).frame(width: 140, height: 170)
                    frame(at: 4.2).frame(width: 140, height: 170)
                    frame(at: 7.5).frame(width: 140, height: 170)
                }
                Text("Пачку не переворачивать: только повернуть на столе на 180°.")
                    .font(.callout.weight(.medium))
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
                    VStack(spacing: 6) {
                        frame(at: t).frame(height: 210)
                        Text(caption(at: t))
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Схема: возьми пачку из выходного лотка, не переворачивая, поверни на столе на 180° и вставь в лоток подачи красным краем вперёд, чистой стороной вверх."))
    }

    private func caption(at t: Double) -> LocalizedStringKey {
        switch t {
        case ..<1.2: return "1. Листы выходят сверху, лицом вниз"
        case ..<2.8: return "2. Возьми всю пачку, не переворачивая"
        case ..<5.0: return "3. Поверни на столе на 180°, как показывает стрелка"
        case ..<6.8: return "4. Вставь в лоток подачи: красный край — в принтер"
        default: return "Чистая сторона вверх, красный край (верх страниц) — в принтер"
        }
    }

    /// Ease in/out между 0 и 1 на отрезке [a, b].
    private func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func frame(at t: Double) -> some View {
        Canvas { ctx, size in
            let k = min(size.width / 420, size.height / 250)
            ctx.translateBy(x: (size.width - 420 * k) / 2, y: (size.height - 250 * k) / 2)
            ctx.scaleBy(x: k, y: k)

            let ink = Theme.ink
            // Принтер.
            let printer = CGRect(x: 100, y: 6, width: 220, height: 104)
            ctx.fill(Path(roundedRect: printer, cornerRadius: 10), with: .color(.gray.opacity(0.18)))
            ctx.stroke(Path(roundedRect: printer, cornerRadius: 10), with: .color(.gray.opacity(0.7)), lineWidth: 1.2)
            ctx.draw(Text("Принтер").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary),
                     at: CGPoint(x: 160, y: 20))
            // Выходной лоток (на крышке).
            let output = CGRect(x: 168, y: 14, width: 84, height: 88)
            ctx.stroke(Path(output), with: .color(.gray.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.draw(Text("выход").font(.system(size: 9)).foregroundColor(.secondary),
                     at: CGPoint(x: 286, y: 36))
            ctx.draw(Text("на крышке").font(.system(size: 9)).foregroundColor(.secondary),
                     at: CGPoint(x: 286, y: 48))
            // Лоток подачи — спереди внизу.
            let cassette = CGRect(x: 162, y: 108, width: 96, height: 10)
            ctx.fill(Path(cassette), with: .color(ink.opacity(0.15)))
            ctx.stroke(Path(cassette), with: .color(ink.opacity(0.8)), lineWidth: 1.2)
            ctx.draw(Text("лоток подачи (спереди внизу)").font(.system(size: 9)).foregroundColor(ink),
                     at: CGPoint(x: 210, y: 128), anchor: .center)
            ctx.draw(Text("ты здесь ↓").font(.system(size: 9)).foregroundColor(.secondary),
                     at: CGPoint(x: 380, y: 236))

            // Положение пачки.
            let outCenter = CGPoint(x: 210, y: 58)
            let table = CGPoint(x: 210, y: 186)
            let insert = CGPoint(x: 210, y: 150)
            let take = ease(t, 1.2, 2.6)
            let turn = ease(t, 2.8, 4.8)
            let push = ease(t, 5.0, 6.6)
            var center = CGPoint(x: outCenter.x + (table.x - outCenter.x) * take,
                                 y: outCenter.y + (table.y - outCenter.y) * take)
            if t >= 5.0 {
                center = CGPoint(x: table.x, y: table.y + (insert.y - table.y) * push)
            }
            let angle = Double.pi * turn
            let lift = (t > 1.2 && t < 2.6) ? 1.0 : 0.0

            // Ось вращения и круговая стрелка.
            if t > 2.5 && t < 5.2 {
                var arc = Path()
                arc.addArc(center: table, radius: 62, startAngle: .degrees(-60), endAngle: .degrees(190), clockwise: false)
                ctx.stroke(arc, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                let tip = CGPoint(x: table.x + 62 * cos(190 * .pi / 180), y: table.y + 62 * sin(190 * .pi / 180))
                var head = Path()
                head.move(to: CGPoint(x: tip.x - 7, y: tip.y + 9))
                head.addLine(to: tip)
                head.addLine(to: CGPoint(x: tip.x + 8, y: tip.y + 6))
                ctx.stroke(head, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: table.x - 4, y: table.y - 4, width: 8, height: 8)), with: .color(.orange))
                ctx.draw(Text("180°").font(.system(size: 11, weight: .bold)).foregroundColor(.orange),
                         at: CGPoint(x: table.x + 76, y: table.y - 30))
                ctx.draw(Text("ось — в центре").font(.system(size: 9)).foregroundColor(.secondary),
                         at: CGPoint(x: 72, y: table.y - 6))
                ctx.draw(Text("не переворачивать!").font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: 72, y: table.y + 7))
            }

            // Пачка: прямоугольник A4 (вид сверху), длинная сторона — вдоль подачи.
            var stack = ctx
            if t >= 5.0 {
                stack.clip(to: Path(CGRect(x: 0, y: cassette.minY, width: 420, height: 250)))
            }
            stack.translateBy(x: center.x, y: center.y)
            stack.rotate(by: .radians(angle))
            let sheet = CGRect(x: -30, y: -42, width: 60, height: 84)
            if lift > 0 {
                stack.fill(Path(sheet.offsetBy(dx: 4, dy: 5)), with: .color(.black.opacity(0.15)))
            }
            for i in stride(from: 3, through: 1, by: -1) {
                let r = sheet.offsetBy(dx: Double(i) * 1.5, dy: Double(i) * 1.5)
                stack.fill(Path(r), with: .color(.white))
                stack.stroke(Path(r), with: .color(.gray.opacity(0.6)), lineWidth: 0.7)
            }
            stack.fill(Path(sheet), with: .color(.white))
            stack.stroke(Path(sheet), with: .color(.gray), lineWidth: 1)
            // Верх страниц: при выходе — край к тебе (снизу картинки).
            let topEdge = CGRect(x: -30, y: 38, width: 60, height: 4)
            stack.fill(Path(topEdge), with: .color(.red))
            stack.draw(Text("чистая").font(.system(size: 9)).foregroundColor(.secondary),
                       at: CGPoint(x: 0, y: -6))
            stack.draw(Text("верх").font(.system(size: 8, weight: .bold)).foregroundColor(.red),
                       at: CGPoint(x: 0, y: 30))

            // Финальная стрелка «верх → в принтер».
            if t >= 6.6 {
                var arrow = Path()
                arrow.move(to: CGPoint(x: 290, y: 200))
                arrow.addLine(to: CGPoint(x: 290, y: 122))
                arrow.move(to: CGPoint(x: 283, y: 131))
                arrow.addLine(to: CGPoint(x: 290, y: 122))
                arrow.addLine(to: CGPoint(x: 297, y: 131))
                ctx.stroke(arrow, with: .color(.red), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ctx.draw(Text("верх → в принтер").font(.system(size: 10, weight: .semibold)).foregroundColor(.red),
                         at: CGPoint(x: 300, y: 212), anchor: .leading)
            }
        }
    }
}
