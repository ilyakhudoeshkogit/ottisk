import Foundation

/// Разбор диапазона страниц, который вводит человек: `1-3, 5, 8-`.
public enum PageRange {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case invalidToken(String)
        case outOfBounds(Int, max: Int)
        case reversed(String)
        case empty

        public var description: String {
            switch self {
            case .invalidToken(let t): return "Не понял «\(t)». Пример: 1-3, 5, 8-"
            case .outOfBounds(let p, let max): return "Страницы \(p) нет — в документе \(max)"
            case .reversed(let t): return "«\(t)»: начало больше конца"
            case .empty: return "В диапазон не попала ни одна страница"
            }
        }
    }

    /// Возвращает отсортированный список страниц (с 1). Пустая строка — все страницы.
    public static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        guard pageCount > 0 else { throw ParseError.empty }
        let cleaned = text
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: ";", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return Array(1...pageCount) }

        var pages = Set<Int>()
        for rawToken in cleaned.split(separator: ",") {
            let token = rawToken.replacingOccurrences(of: " ", with: "")
            if token.isEmpty { continue }
            if let dash = token.firstIndex(of: "-") {
                let left = String(token[..<dash])
                let right = String(token[token.index(after: dash)...])
                let start = left.isEmpty ? 1 : Int(left)
                let end = right.isEmpty ? pageCount : Int(right)
                guard let s = start, let e = end, s > 0, e > 0, !right.contains("-") else {
                    throw ParseError.invalidToken(token)
                }
                guard s <= e else { throw ParseError.reversed(token) }
                guard s <= pageCount else { throw ParseError.outOfBounds(s, max: pageCount) }
                guard e <= pageCount else { throw ParseError.outOfBounds(e, max: pageCount) }
                pages.formUnion(s...e)
            } else {
                guard let p = Int(token), p > 0 else { throw ParseError.invalidToken(token) }
                guard p <= pageCount else { throw ParseError.outOfBounds(p, max: pageCount) }
                pages.insert(p)
            }
        }
        guard !pages.isEmpty else { throw ParseError.empty }
        return pages.sorted()
    }

    /// Сжимает список страниц в строку для `lp -P`: [1,2,3,5] → "1-3,5".
    public static func cupsString(_ pages: [Int]) -> String {
        let sorted = Array(Set(pages)).sorted()
        guard var start = sorted.first else { return "" }
        var parts: [String] = []
        var prev = start
        for p in sorted.dropFirst() {
            if p == prev + 1 { prev = p; continue }
            parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
            start = p; prev = p
        }
        parts.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return parts.joined(separator: ",")
    }

    /// Все ли страницы документа выбраны (тогда `-P` не нужен).
    public static func isAll(_ pages: [Int], pageCount: Int) -> Bool {
        pages.count == pageCount && pages.first == 1 && pages.last == pageCount
    }
}
