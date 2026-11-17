import Foundation

/// Запуск консольных утилит (`lp`, `lpstat`, …) без блокировки интерфейса.
enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    enum Failure: LocalizedError {
        case notFound(String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let path): return "Не найдена утилита \(path)"
            case .timedOut(let path): return "\(path) не ответила вовремя"
            }
        }
    }

    private final class Box: @unchecked Sendable {
        var data = Data()
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 20) async throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw Failure.notFound(path) }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                // Английские сообщения CUPS — их проще разбирать; UTF-8 — для кириллицы в именах.
                env["LANG"] = "en_US.UTF-8"
                env["LC_ALL"] = "en_US.UTF-8"
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timedOut = Box()
                let deadline = DispatchWorkItem {
                    if process.isRunning {
                        timedOut.data = Data([1])
                        process.terminate()
                        // Не ответила на SIGTERM — через 2 с SIGKILL, чтобы ожидание точно закончилось.
                        let pid = process.processIdentifier
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            if process.isRunning { kill(pid, SIGKILL) }
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

                // Читаем оба потока параллельно, чтобы не упереться в буфер pipe.
                let outBox = Box()
                let outHandle = outPipe.fileHandleForReading
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outBox.data = outHandle.readDataToEndOfFile()
                    group.leave()
                }
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                deadline.cancel()

                if !timedOut.data.isEmpty {
                    continuation.resume(throwing: Failure.timedOut(path))
                    return
                }
                continuation.resume(returning: Output(status: process.terminationStatus,
                                                      stdout: String(decoding: outBox.data, as: UTF8.self),
                                                      stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}
