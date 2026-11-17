import Foundation

/// Настройки сканирования (сам скан — через ImageCaptureCore в приложении).
public struct ScanOptions: Codable, Equatable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable {
        case pdf, png, jpeg
        public var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
        public var uti: String {
            switch self {
            case .pdf: return "com.adobe.pdf"
            case .png: return "public.png"
            case .jpeg: return "public.jpeg"
            }
        }
        public var title: String { rawValue.uppercased() }
    }

    public enum ColorMode: String, Codable, CaseIterable, Sendable {
        case color, gray, blackWhite
        public var title: String {
            switch self {
            case .color: return "Цветной"
            case .gray: return "Оттенки серого"
            case .blackWhite: return "Чёрно-белый"
            }
        }
    }

    public var dpi: Int = 300
    public var format: Format = .pdf
    public var colorMode: ColorMode = .gray

    public init(dpi: Int = 300, format: Format = .pdf, colorMode: ColorMode = .gray) {
        self.dpi = dpi
        self.format = format
        self.colorMode = colorMode
    }

    /// Разрешения, которые предлагаем. Документы — 300, фото — 600, быстро — 150.
    public static let commonDPI = [75, 150, 200, 300, 600, 1200]

    /// Ближайшее разрешение, которое сканер реально поддерживает.
    public static func nearestSupported(_ wanted: Int, supported: [Int]) -> Int {
        guard !supported.isEmpty else { return wanted }
        return supported.min { lhs, rhs in
            let dl = abs(lhs - wanted), dr = abs(rhs - wanted)
            return dl == dr ? lhs > rhs : dl < dr
        }!
    }

    /// Из `commonDPI` оставляем то, что поддерживает сканер; если пересечения нет — сам список сканера.
    public static func offeredDPI(supported: [Int]) -> [Int] {
        guard !supported.isEmpty else { return commonDPI }
        let set = Set(supported)
        let common = commonDPI.filter { set.contains($0) }
        return common.isEmpty ? supported.sorted() : common
    }

    /// Примерный размер A4 в пикселях — для подсказки «≈ 2480 × 3508».
    public func a4Pixels() -> (width: Int, height: Int) {
        (Int((210 / 25.4 * Double(dpi)).rounded()), Int((297 / 25.4 * Double(dpi)).rounded()))
    }

    /// Имя файла: «Скан 2026-11-13 14-05-33». Без двоеточий — Finder их не любит.
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "Скан %04d-%02d-%02d %02d-%02d-%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Не перезаписывать: «Скан …», «Скан … (2)», «Скан … (3)».
    public static func uniqueName(base: String, ext: String, existing: Set<String>) -> String {
        var candidate = "\(base).\(ext)"
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(base) (\(n)).\(ext)"
            n += 1
        }
        return candidate
    }
}
