import Foundation
import OttiskCore

/// Обёртка над утилитами CUPS, которые есть в любой macOS.
enum CUPSClient {
    static let lpPath = "/usr/bin/lp"
    static let lpstatPath = "/usr/bin/lpstat"
    static let lpoptionsPath = "/usr/bin/lpoptions"
    static let cancelPath = "/usr/bin/cancel"
    static let cupsenablePath = "/usr/sbin/cupsenable"
    static let cupsacceptPath = "/usr/sbin/cupsaccept"

    /// Быстрые запросы состояния: если CUPS завис, не ждём дольше этого.
    static let queryTimeout: TimeInterval = 10

    struct CommandError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func cleaned(_ output: ProcessRunner.Output) -> String {
        let text = (output.stderr.isEmpty ? output.stdout : output.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "код \(output.status)" : text
    }

    /// Все локальные очереди с состоянием.
    static func printers() async throws -> [Printer] {
        let status = try await ProcessRunner.run(lpstatPath, ["-p"], timeout: queryTimeout)
        if status.status != 0 {
            let text = status.stderr + status.stdout
            if text.localizedCaseInsensitiveContains("No destinations") { return [] }
            throw CommandError(message: "lpstat: " + cleaned(status))
        }
        let lines = CUPSParsers.parsePrinterStatus(status.stdout)
        let defaultOut = try? await ProcessRunner.run(lpstatPath, ["-d"], timeout: queryTimeout)
        let defaultName = defaultOut.flatMap { CUPSParsers.parseDefaultDestination($0.stdout) }

        var result: [Printer] = []
        for line in lines {
            var printer: Printer
            if let attrs = try? await ProcessRunner.run(lpoptionsPath, ["-p", line.name], timeout: queryTimeout), attrs.status == 0 {
                printer = CUPSParsers.printer(named: line.name,
                                              attributes: CUPSParsers.parseKeyValues(attrs.stdout),
                                              isDefault: line.name == defaultName)
            } else {
                printer = Printer(name: line.name, isDefault: line.name == defaultName)
            }
            if let state = line.stateCode { printer.stateCode = state }
            if printer.stateMessage == nil { printer.stateMessage = line.message }
            if printer.info == nil { printer.info = line.description }
            if printer.location == nil { printer.location = line.location }
            if printer.stateReasons.isEmpty { printer.stateReasons = line.alerts }
            result.append(printer)
        }
        return result
    }

    /// ID заданий, которые печатаются прямо сейчас.
    static func activeJobIDs() async -> Set<String> {
        guard let out = try? await ProcessRunner.run(lpstatPath, ["-p"], timeout: queryTimeout) else { return [] }
        return Set(CUPSParsers.parsePrinterStatus(out.stdout).compactMap(\.currentJobID))
    }

    /// Незавершённые задания всех принтеров.
    static func jobs() async throws -> [PrintJob] {
        let out = try await ProcessRunner.run(lpstatPath, ["-o"], timeout: queryTimeout)
        if out.status != 0 {
            let text = out.stderr + out.stdout
            if text.localizedCaseInsensitiveContains("No destinations") { return [] }
            throw CommandError(message: "lpstat -o: " + cleaned(out))
        }
        let active = await activeJobIDs()
        return CUPSParsers.parseJobs(out.stdout, activeJobIDs: active)
    }

    /// Опции драйвера (`lpoptions -l`).
    static func options(for printer: String) async throws -> [PrinterOption] {
        let out = try await ProcessRunner.run(lpoptionsPath, ["-p", printer, "-l"], timeout: queryTimeout)
        guard out.status == 0 else { throw CommandError(message: "lpoptions: " + cleaned(out)) }
        return CUPSParsers.parseOptionList(out.stdout)
    }

    /// Отправляет задание, возвращает ID (`Canon_MF3010-42`).
    static func submit(arguments: [String]) async throws -> String {
        let out = try await ProcessRunner.run(lpPath, arguments, timeout: 120)
        guard out.status == 0 else { throw CommandError(message: "lp: " + cleaned(out)) }
        return CUPSParsers.parseRequestID(out.stdout) ?? "?"
    }

    static func cancel(jobID: String) async throws {
        let out = try await ProcessRunner.run(cancelPath, [jobID])
        guard out.status == 0 else { throw CommandError(message: "cancel: " + cleaned(out)) }
    }

    static func cancelAll(printer: String) async throws {
        let out = try await ProcessRunner.run(cancelPath, ["-a", printer])
        guard out.status == 0 else { throw CommandError(message: "cancel -a: " + cleaned(out)) }
    }

    /// Снимает паузу с очереди (бывает после отключения USB). Может требовать прав администратора.
    static func resume(printer: String) async throws {
        let out = try await ProcessRunner.run(cupsenablePath, [printer])
        guard out.status == 0 else { throw CommandError(message: "cupsenable: " + cleaned(out)) }
        let accept = try await ProcessRunner.run(cupsacceptPath, [printer])
        guard accept.status == 0 else { throw CommandError(message: "cupsaccept: " + cleaned(accept)) }
    }
}
