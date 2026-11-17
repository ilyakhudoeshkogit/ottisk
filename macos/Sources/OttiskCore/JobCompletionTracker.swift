import Foundation

/// Следит за нашими заданиями и сообщает, какие закончились.
///
/// `lpstat -o` показывает только незавершённые задания. Задание, которое мы
/// отправили и которое пропало из списка, считаем напечатанным, если его
/// не отменили через Оттиск. Короткие задания могут пролететь между опросами —
/// поэтому «пропало» считается и для тех, которые мы ни разу не видели в очереди.
public struct JobCompletionTracker: Equatable, Sendable {
    public struct Finished: Equatable, Sendable {
        public var jobID: String
        public var title: String
    }

    /// ID → название.
    public private(set) var watched: [String: String] = [:]

    public init() {}

    public mutating func watch(_ jobID: String, title: String) {
        guard jobID != "?" && !jobID.isEmpty else { return }
        watched[jobID] = title
    }

    /// Отменённые не уведомляем.
    public mutating func forget(_ jobID: String) {
        watched[jobID] = nil
    }

    public mutating func forgetAll(printer: String) {
        watched = watched.filter { !$0.key.hasPrefix(printer + "-") }
    }

    /// Новый снимок очереди → список завершённых (по возрастанию номера задания).
    public mutating func update(with jobs: [PrintJob]) -> [Finished] {
        let present = Set(jobs.map(\.id))
        let done = watched.filter { !present.contains($0.key) }
        for id in done.keys { watched[id] = nil }
        return done.map { Finished(jobID: $0.key, title: $0.value) }
            .sorted { Self.number($0.jobID) < Self.number($1.jobID) }
    }

    static func number(_ id: String) -> Int {
        Int(id.split(separator: "-").last ?? "") ?? 0
    }
}
