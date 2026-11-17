import Foundation

/// Превращает сырые `printer-state` / `printer-state-reasons` в понятное состояние.
public enum PrinterStatusInterpreter {
    /// Убирает суффиксы `-error`, `-warning`, `-report` (RFC 8011, 5.4.12).
    public static func baseReason(_ reason: String) -> String {
        var r = reason.trimmingCharacters(in: .whitespaces).lowercased()
        for suffix in ["-error", "-warning", "-report"] where r.hasSuffix(suffix) {
            r.removeLast(suffix.count)
            break
        }
        return r
    }

    public static func condition(stateCode: Int?, reasons: [String], message: String?, accepting: Bool) -> PrinterCondition {
        let base = Set(reasons.map(baseReason).filter { !$0.isEmpty && $0 != "none" })

        // Самое важное — сверху.
        if base.contains("media-jam") { return .paperJam }
        if base.contains("media-empty") || base.contains("media-needed") { return .paperOut }
        if base.contains("cover-open") || base.contains("door-open") || base.contains("interlock-open") { return .coverOpen }
        if base.contains("toner-empty") || base.contains("marker-supply-empty") { return .tonerEmpty }
        if base.contains("offline") || base.contains("connecting-to-device") || base.contains("shutdown") {
            return .offline
        }
        if base.contains("paused") || stateCode == 5 || !accepting {
            // Остановленная очередь с сообщением — показываем сообщение.
            if let message, !message.isEmpty, stateCode == 5, !base.contains("paused") {
                return .error(message)
            }
            return .paused
        }
        if stateCode == 4 { return .printing }
        if base.contains("toner-low") || base.contains("marker-supply-low") { return .tonerLow }
        if base.contains("other") {
            return .error(message ?? "")
        }
        if stateCode == 3 { return .ready }
        if stateCode == nil && base.isEmpty { return .unknown }
        return .ready
    }
}
