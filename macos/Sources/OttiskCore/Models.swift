import Foundation

/// Состояние принтера по данным CUPS (`printer-state` + `printer-state-reasons`).
public enum PrinterCondition: Equatable, Sendable {
    case ready
    case printing
    case paused
    case offline
    case paperOut
    case paperJam
    case coverOpen
    case tonerLow
    case tonerEmpty
    case error(String)
    case unknown

    /// Короткая подпись для интерфейса (по-русски).
    public var title: String {
        switch self {
        case .ready: return "Готов"
        case .printing: return "Печатает"
        case .paused: return "Приостановлен"
        case .offline: return "Не подключён"
        case .paperOut: return "Нет бумаги"
        case .paperJam: return "Замялась бумага"
        case .coverOpen: return "Открыта крышка"
        case .tonerLow: return "Мало тонера"
        case .tonerEmpty: return "Закончился тонер"
        case .error(let text): return text.isEmpty ? "Ошибка" : text
        case .unknown: return "Неизвестно"
        }
    }

    /// Можно ли сейчас спокойно отправлять задание.
    public var isUsable: Bool {
        switch self {
        case .ready, .printing, .tonerLow: return true
        default: return false
        }
    }

    /// Уровень серьёзности: 0 — норма, 1 — предупреждение, 2 — ошибка.
    public var severity: Int {
        switch self {
        case .ready, .printing: return 0
        case .tonerLow, .paused, .unknown: return 1
        default: return 2
        }
    }
}

/// Принтер (destination) CUPS.
public struct Printer: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { name }
    /// Системное имя очереди, например `Canon_MF3010`.
    public var name: String
    /// Человекочитаемое имя (`printer-info`), если есть.
    public var info: String?
    public var makeAndModel: String?
    public var location: String?
    public var deviceURI: String?
    public var isDefault: Bool
    public var isAcceptingJobs: Bool
    /// 3 — idle, 4 — processing, 5 — stopped.
    public var stateCode: Int?
    public var stateReasons: [String]
    /// Сообщение принтера (`printer-state-message` или строка с табом из `lpstat -p`).
    public var stateMessage: String?

    public init(name: String, info: String? = nil, makeAndModel: String? = nil, location: String? = nil,
                deviceURI: String? = nil, isDefault: Bool = false, isAcceptingJobs: Bool = true,
                stateCode: Int? = nil, stateReasons: [String] = [], stateMessage: String? = nil) {
        self.name = name
        self.info = info
        self.makeAndModel = makeAndModel
        self.location = location
        self.deviceURI = deviceURI
        self.isDefault = isDefault
        self.isAcceptingJobs = isAcceptingJobs
        self.stateCode = stateCode
        self.stateReasons = stateReasons
        self.stateMessage = stateMessage
    }

    public var displayName: String {
        if let info, !info.isEmpty { return info }
        return name.replacingOccurrences(of: "_", with: " ")
    }

    /// Подключён по USB (по `device-uri`).
    public var isUSB: Bool { deviceURI?.lowercased().hasPrefix("usb:") ?? false }

    /// Похоже на Canon MF3010 — для подсказок про ручную двустороннюю печать.
    public var looksLikeMF3010: Bool {
        let haystack = [name, info ?? "", makeAndModel ?? "", deviceURI ?? ""].joined(separator: " ").lowercased()
        return haystack.contains("mf3010") || haystack.contains("mf 3010") || haystack.contains("mf%203010")
    }

    public var condition: PrinterCondition {
        PrinterStatusInterpreter.condition(stateCode: stateCode, reasons: stateReasons,
                                           message: stateMessage, accepting: isAcceptingJobs)
    }
}

/// Опция драйвера из `lpoptions -p <принтер> -l`.
public struct PrinterOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var choices: [String]
    public var defaultChoice: String?

    public init(key: String, label: String, choices: [String], defaultChoice: String?) {
        self.key = key
        self.label = label
        self.choices = choices
        self.defaultChoice = defaultChoice
    }
}

/// Задание в очереди (`lpstat -o`).
public struct PrintJob: Identifiable, Equatable, Hashable, Sendable {
    /// Например `Canon_MF3010-42`.
    public var id: String
    public var printer: String
    public var number: Int?
    public var user: String
    public var sizeBytes: Int?
    public var dateText: String
    /// Если очередь сейчас печатает именно это задание.
    public var isActive: Bool

    public init(id: String, printer: String, number: Int?, user: String, sizeBytes: Int?, dateText: String, isActive: Bool = false) {
        self.id = id
        self.printer = printer
        self.number = number
        self.user = user
        self.sizeBytes = sizeBytes
        self.dateText = dateText
        self.isActive = isActive
    }
}
