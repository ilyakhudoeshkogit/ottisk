import Foundation

/// Водяной знак поверх каждой страницы («КОПИЯ», «ЧЕРНОВИК», «Для БГУИР»…).
public struct Watermark: Codable, Equatable, Sendable {
    public var text: String
    /// 0.05…0.6 — насколько заметно.
    public var opacity: Double
    /// Угол в градусах, против часовой стрелки.
    public var angle: Double

    public init(text: String, opacity: Double = 0.15, angle: Double = 45) {
        self.text = text
        self.opacity = opacity
        self.angle = angle
    }

    public static let suggestions = ["КОПИЯ", "ЧЕРНОВИК", "ОБРАЗЕЦ", "НЕ ДЛЯ ПЕЧАТИ"]
    public static let opacityRange: ClosedRange<Double> = 0.05...0.6

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isActive: Bool { !trimmedText.isEmpty }
    public var clampedOpacity: Double { min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) }

    /// Размер шрифта, чтобы текст лёг по диагонали страницы и не вылез за край.
    /// Ширина символа берётся ≈0.62 кегля (жирный гротеск) — с запасом.
    public func fontSize(pageWidth: Double, pageHeight: Double) -> Double {
        let length = Double(max(trimmedText.count, 1))
        let radians = angle * .pi / 180
        // Сколько места вдоль выбранного направления до края страницы.
        let cosA = abs(cos(radians)), sinA = abs(sin(radians))
        let along = min(cosA > 0.0001 ? pageWidth / cosA : .infinity,
                        sinA > 0.0001 ? pageHeight / sinA : .infinity)
        let size = along * 0.8 / (length * 0.62)
        return min(max(size, 12), 160)
    }
}
