import Foundation

/// Разбор текстового вывода утилит CUPS (`lpstat`, `lpoptions`, `lp`).
/// Утилиты нужно запускать с `LC_ALL=C`, иначе фразы будут локализованы.
public enum CUPSParsers {

    // MARK: lpstat -p [-l]

    public struct PrinterLine: Equatable, Sendable {
        public var name: String
        public var stateCode: Int?          // 3 idle, 4 processing, 5 stopped
        public var currentJobID: String?
        public var message: String?
        public var description: String?
        public var location: String?
        public var alerts: [String]
    }

    /// `lpstat -p` / `lpstat -l -p`.
    ///
    ///     printer Canon_MF3010 is idle.  enabled since Fri Nov 13 10:00:00 2026
    ///     printer Canon_MF3010 now printing Canon_MF3010-12.  enabled since ...
    ///     printer Canon_MF3010 disabled since Fri Nov 13 10:00:00 2026 -
    ///     	Paused
    public static func parsePrinterStatus(_ output: String) -> [PrinterLine] {
        var result: [PrinterLine] = []
        for rawLine in output.components(separatedBy: .newlines) {
            if rawLine.hasPrefix("printer ") {
                let rest = String(rawLine.dropFirst("printer ".count))
                let parts = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard let name = parts.first else { continue }
                var line = PrinterLine(name: name, stateCode: nil, currentJobID: nil, message: nil,
                                       description: nil, location: nil, alerts: [])
                let tail = parts.dropFirst().joined(separator: " ")
                if tail.hasPrefix("is idle") {
                    line.stateCode = 3
                } else if tail.hasPrefix("now printing") {
                    line.stateCode = 4
                    if parts.count > 3 {
                        var job = parts[3]
                        while job.hasSuffix(".") { job.removeLast() }
                        line.currentJobID = job.isEmpty ? nil : job
                    }
                } else if tail.hasPrefix("disabled") {
                    line.stateCode = 5
                }
                result.append(line)
            } else if rawLine.hasPrefix("\t") || rawLine.hasPrefix(" "), !result.isEmpty {
                let text = rawLine.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                var last = result.removeLast()
                if let value = value(after: "Description:", in: text) {
                    last.description = value.isEmpty ? nil : value
                } else if let value = value(after: "Location:", in: text) {
                    last.location = value.isEmpty ? nil : value
                } else if let value = value(after: "Alerts:", in: text) {
                    last.alerts = value.split(whereSeparator: { $0 == " " || $0 == "," })
                        .map(String.init).filter { $0 != "none" }
                } else if text.contains(":") && isKnownLongField(text) {
                    // Прочие поля `lpstat -l` (Form mounted, Content types, ...) — пропускаем.
                } else if last.message == nil {
                    last.message = text
                }
                result.append(last)
            }
        }
        return result
    }

    private static let longFields = ["Form mounted:", "Content types:", "Printer types:", "Connection:",
                                     "Interface:", "On fault:", "After fault:", "Users allowed:",
                                     "Users denied:", "Forms allowed:", "Banner required", "Charset sets:",
                                     "Default pitch:", "Default page size:", "Default port settings:"]

    private static func isKnownLongField(_ text: String) -> Bool {
        longFields.contains { text.hasPrefix($0) }
    }

    private static func value(after prefix: String, in text: String) -> String? {
        guard text.hasPrefix(prefix) else { return nil }
        return text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    // MARK: lpstat -d

    /// `system default destination: Canon_MF3010` → `Canon_MF3010`.
    public static func parseDefaultDestination(_ output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let marker = "system default destination:"
            if let range = line.range(of: marker) {
                let name = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    // MARK: lpstat -v

    /// `device for Canon_MF3010: usb://Canon/MF3010?serial=…` → [имя: uri].
    public static func parseDeviceURIs(_ output: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            guard line.hasPrefix("device for ") else { continue }
            let rest = line.dropFirst("device for ".count)
            guard let colon = rest.firstIndex(of: ":") else { continue }
            let name = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
            let uri = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { map[name] = uri }
        }
        return map
    }

    // MARK: lpstat -a

    /// `Canon_MF3010 accepting requests since …` / `… not accepting requests …`.
    public static func parseAccepting(_ output: String) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for line in output.components(separatedBy: .newlines) where !line.hasPrefix("\t") && !line.hasPrefix(" ") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            if parts[1] == "accepting" { map[parts[0]] = true }
            else if parts[1] == "not", parts.count >= 3, parts[2] == "accepting" { map[parts[0]] = false }
        }
        return map
    }

    // MARK: lpstat -o

    /// `Canon_MF3010-12   ilya   102400   Fri Nov 13 10:00:00 2026`.
    public static func parseJobs(_ output: String, activeJobIDs: Set<String> = []) -> [PrintJob] {
        var jobs: [PrintJob] = []
        for line in output.components(separatedBy: .newlines) {
            guard !line.isEmpty, !line.hasPrefix("\t"), !line.hasPrefix(" ") else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3, let (printer, number) = splitJobID(parts[0]) else { continue }
            let size = Int(parts[2])
            let dateText = parts.count > 3 ? parts[3...].joined(separator: " ") : ""
            jobs.append(PrintJob(id: parts[0], printer: printer, number: number, user: parts[1],
                                 sizeBytes: size, dateText: dateText,
                                 isActive: activeJobIDs.contains(parts[0])))
        }
        return jobs
    }

    /// `Canon_MF3010-12` → (`Canon_MF3010`, 12). Имя принтера может содержать дефисы.
    public static func splitJobID(_ id: String) -> (String, Int)? {
        guard let dash = id.lastIndex(of: "-") else { return nil }
        let printer = String(id[..<dash])
        guard !printer.isEmpty, let number = Int(id[id.index(after: dash)...]) else { return nil }
        return (printer, number)
    }

    // MARK: lp

    /// `request id is Canon_MF3010-12 (1 file(s))` → `Canon_MF3010-12`.
    public static func parseRequestID(_ output: String) -> String? {
        guard let range = output.range(of: "request id is ") else { return nil }
        let rest = output[range.upperBound...]
        let id = rest.prefix { !$0.isWhitespace && $0 != "(" }
        return id.isEmpty ? nil : String(id)
    }

    // MARK: lpoptions -p NAME -l

    /// `PageSize/Media Size: Letter *A4 Legal` → опция с выбором по умолчанию.
    public static func parseOptionList(_ output: String) -> [PrinterOption] {
        var options: [PrinterOption] = []
        for line in output.components(separatedBy: .newlines) {
            guard let colon = line.range(of: ": ") ?? line.range(of: ":", options: .backwards) else { continue }
            let head = String(line[..<colon.lowerBound])
            let tail = String(line[colon.upperBound...])
            guard !head.isEmpty else { continue }
            let key: String
            let label: String
            if let slash = head.firstIndex(of: "/") {
                key = String(head[..<slash])
                label = String(head[head.index(after: slash)...])
            } else {
                key = head
                label = head
            }
            guard !key.contains(" ") else { continue }
            var choices: [String] = []
            var def: String?
            for token in tail.split(separator: " ", omittingEmptySubsequences: true) {
                var choice = String(token)
                if choice.hasPrefix("*") {
                    choice.removeFirst()
                    def = choice
                }
                if !choice.isEmpty { choices.append(choice) }
            }
            guard !choices.isEmpty else { continue }
            options.append(PrinterOption(key: key, label: label, choices: choices, defaultChoice: def))
        }
        return options
    }

    // MARK: lpoptions -p NAME

    /// Разбирает строку вида `copies=1 printer-info='Canon MF3010' printer-state=3 …`.
    /// Понимает одинарные/двойные кавычки и экранирование обратным слэшем.
    public static func parseKeyValues(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingValue = false
        var quote: Character?
        var escaping = false

        func flush() {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { result[k] = readingValue ? value : "" }
            key = ""; value = ""; readingValue = false
        }

        for ch in output {
            if escaping {
                if readingValue { value.append(ch) } else { key.append(ch) }
                escaping = false
                continue
            }
            if ch == "\\" { escaping = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { value.append(ch) }
                continue
            }
            if readingValue && (ch == "'" || ch == "\"") { quote = ch; continue }
            if ch == " " || ch == "\n" || ch == "\t" {
                if !key.isEmpty { flush() }
                continue
            }
            if ch == "=" && !readingValue { readingValue = true; continue }
            if readingValue { value.append(ch) } else { key.append(ch) }
        }
        flush()
        return result
    }

    /// Собирает принтер из атрибутов `lpoptions -p NAME`.
    public static func printer(named name: String, attributes a: [String: String], isDefault: Bool) -> Printer {
        let reasons = (a["printer-state-reasons"] ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "none" }
        let accepting: Bool = {
            guard let v = a["printer-is-accepting-jobs"]?.lowercased() else { return true }
            return v == "true" || v == "1" || v == "yes"
        }()
        return Printer(name: name,
                       info: a["printer-info"].flatMap { $0.isEmpty ? nil : $0 },
                       makeAndModel: a["printer-make-and-model"].flatMap { $0.isEmpty ? nil : $0 },
                       location: a["printer-location"].flatMap { $0.isEmpty ? nil : $0 },
                       deviceURI: a["device-uri"].flatMap { $0.isEmpty ? nil : $0 },
                       isDefault: isDefault,
                       isAcceptingJobs: accepting,
                       stateCode: a["printer-state"].flatMap { Int($0) },
                       stateReasons: reasons,
                       stateMessage: a["printer-state-message"].flatMap { $0.isEmpty ? nil : $0 })
    }
}
