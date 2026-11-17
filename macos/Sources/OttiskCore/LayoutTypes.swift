import Foundation

/// Миллиметры ↔ пункты PDF (1 pt = 1/72 дюйма).
public enum Units {
    public static let pointsPerMM = 72.0 / 25.4
    public static func pt(_ mm: Double) -> Double { mm * pointsPerMM }
    public static func mm(_ pt: Double) -> Double { pt / pointsPerMM }
}

/// Размер в пунктах.
public struct LayoutSize: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public var isLandscape: Bool { width > height }
    public var swapped: LayoutSize { LayoutSize(width: height, height: width) }
    public var portrait: LayoutSize { isLandscape ? swapped : self }
    public var landscape: LayoutSize { isLandscape ? self : swapped }

    public static let a4 = LayoutSize(width: 595.28, height: 841.89)
    public static let a5 = LayoutSize(width: 419.53, height: 595.28)
    public static let a3 = LayoutSize(width: 841.89, height: 1190.55)
    public static let letter = LayoutSize(width: 612, height: 792)
    public static let legal = LayoutSize(width: 612, height: 1008)

    /// Размер листа по значению опции `media`/`PageSize` («A4», «iso_a4_210x297mm», «Letter»…). По умолчанию A4.
    public static func sheet(forMedia media: String?) -> LayoutSize {
        let m = (media ?? "").lowercased()
        if m.contains("a5") { return .a5 }
        if m.contains("a3") { return .a3 }
        if m.contains("legal") { return .legal }
        if m.contains("letter") { return .letter }
        return .a4
    }
}

/// Прямоугольник в пунктах. Начало координат — левый нижний угол (как в PDF).
public struct LayoutRect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(size: LayoutSize) {
        self.init(x: 0, y: 0, width: size.width, height: size.height)
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func inset(top: Double, left: Double, bottom: Double, right: Double) -> LayoutRect {
        LayoutRect(x: x + left, y: y + bottom, width: max(width - left - right, 0), height: max(height - top - bottom, 0))
    }

    public func union(_ other: LayoutRect) -> LayoutRect {
        let x0 = min(minX, other.minX), y0 = min(minY, other.minY)
        let x1 = max(maxX, other.maxX), y1 = max(maxY, other.maxY)
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func intersection(_ other: LayoutRect) -> LayoutRect {
        let x0 = max(minX, other.minX), y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX), y1 = min(maxY, other.maxY)
        return LayoutRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }

    /// Целиком внутри `other` (с допуском в пунктах).
    public func isInside(_ other: LayoutRect, tolerance: Double = 0.01) -> Bool {
        minX >= other.minX - tolerance && minY >= other.minY - tolerance
            && maxX <= other.maxX + tolerance && maxY <= other.maxY + tolerance
    }
}

/// Поля листа в миллиметрах.
public struct PageMargins: Codable, Equatable, Hashable, Sendable {
    public var top: Double
    public var bottom: Double
    public var left: Double
    public var right: Double

    public init(top: Double = 0, bottom: Double = 0, left: Double = 0, right: Double = 0) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public init(all: Double) { self.init(top: all, bottom: all, left: all, right: all) }

    public static let zero = PageMargins()
    /// ГОСТ 7.32-2017, п. 6.1.1: левое 30, правое 15, верхнее и нижнее 20 мм.
    /// Те же поля — в СТП БГУИР 01-2024, п. 2.1.1.
    public static let gost7_32 = PageMargins(top: 20, bottom: 20, left: 30, right: 15)

    public var isZero: Bool { top <= 0 && bottom <= 0 && left <= 0 && right <= 0 }

    /// Поле не меньше, чем у другого (по каждой стороне).
    public func atLeast(_ other: PageMargins) -> PageMargins {
        PageMargins(top: max(top, other.top), bottom: max(bottom, other.bottom),
                    left: max(left, other.left), right: max(right, other.right))
    }

    public var clamped: PageMargins {
        func c(_ v: Double) -> Double { min(max(v, 0), 80) }
        return PageMargins(top: c(top), bottom: c(bottom), left: c(left), right: c(right))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        top = try c.decodeIfPresent(Double.self, forKey: .top) ?? 0
        bottom = try c.decodeIfPresent(Double.self, forKey: .bottom) ?? 0
        left = try c.decodeIfPresent(Double.self, forKey: .left) ?? 0
        right = try c.decodeIfPresent(Double.self, forKey: .right) ?? 0
    }
}

/// Масштаб страницы в ячейке.
public enum ScaleMode: String, Codable, CaseIterable, Sendable {
    /// Вписать в доступное место (увеличить или уменьшить).
    case fit
    /// 100 %, как в файле.
    case actual
    /// Свой процент.
    case custom

    public var title: String {
        switch self {
        case .fit: return "По размеру"
        case .actual: return "100 %"
        case .custom: return "Свой %"
        }
    }
}

/// Какие страницы печатать.
public enum PageParity: String, Codable, CaseIterable, Sendable {
    case all, odd, even

    public var title: String {
        switch self {
        case .all: return "Все"
        case .odd: return "Нечётные"
        case .even: return "Чётные"
        }
    }
}

/// Порядок раскладки при «N на листе».
public enum NUpOrder: String, Codable, CaseIterable, Sendable {
    /// Как текст: слева направо, потом вниз (Z).
    case rows
    /// Сверху вниз, потом вправо (N).
    case columns

    public var title: String {
        switch self {
        case .rows: return "Z: по строкам"
        case .columns: return "N: по столбцам"
        }
    }
}

/// Где переплёт (дырокол, скоросшиватель).
public enum BindingEdge: String, Codable, CaseIterable, Sendable {
    case left, top

    public var title: String {
        switch self {
        case .left: return "Слева"
        case .top: return "Сверху"
        }
    }
}

public enum NumberPosition: String, Codable, CaseIterable, Sendable {
    case bottomCenter, bottomRight, topRight

    public var title: String {
        switch self {
        case .bottomCenter: return "Внизу по центру"
        case .bottomRight: return "Внизу справа"
        case .topRight: return "Вверху справа"
        }
    }
}

/// Нумерация страниц поверх документа.
///
/// Номер привязан к странице документа: страница p получает `startAt + p - 1`.
/// Поэтому, если перепечатать одну страницу, номер на ней будет тот же.
/// Первые `skipFirst` страниц считаются, но номер на них не ставится
/// (титульный лист по ГОСТ 7.32-2017, п. 6.3.2).
public struct PageNumbering: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var startAt: Int
    public var skipFirst: Int
    public var position: NumberPosition

    public init(enabled: Bool = false, startAt: Int = 1, skipFirst: Int = 0, position: NumberPosition = .bottomCenter) {
        self.enabled = enabled
        self.startAt = startAt
        self.skipFirst = skipFirst
        self.position = position
    }

    /// Номер для страницы документа (с 1) или nil, если номер не ставится.
    public func label(forPage page: Int) -> String? {
        guard enabled, page > max(skipFirst, 0) else { return nil }
        return String(startAt + page - 1)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startAt = try c.decodeIfPresent(Int.self, forKey: .startAt) ?? 1
        skipFirst = try c.decodeIfPresent(Int.self, forKey: .skipFirst) ?? 0
        position = (try? c.decodeIfPresent(NumberPosition.self, forKey: .position)) ?? .bottomCenter
    }
}

/// Усиление для сканов: темнее тонкие линии и выше контраст. 0 — выключено.
public enum ScanEnhance {
    public static let levels = 0...3

    /// Множитель контраста для CIColorControls.
    public static func contrast(level: Int) -> Double {
        1.0 + 0.3 * Double(min(max(level, 0), 3))
    }

    /// Радиус «утолщения» тёмных линий (CIMorphologyMinimum) в пикселях при заданном dpi.
    /// Уровень 1 ≈ 0,05 мм, 3 ≈ 0,15 мм.
    public static func thickenRadius(level: Int, dpi: Double) -> Double {
        let mm = 0.05 * Double(min(max(level, 0), 3))
        return mm / 25.4 * dpi
    }
}
