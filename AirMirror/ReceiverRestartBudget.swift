import Foundation

/// Starting a process is not recovery: only a stable run or a connection resets failures.
struct ReceiverRestartBudget {
    private(set) var failures = 0
    private var startedAt: Date?

    mutating func didStart(now: Date = Date()) { startedAt = now }

    mutating func reset() {
        failures = 0
        startedAt = nil
    }

    mutating func retryDelayAfterExit(now: Date = Date()) -> TimeInterval? {
        if let startedAt, now.timeIntervalSince(startedAt) >= 30 { failures = 0 }
        failures += 1
        guard failures < 6 else { return nil }
        return min(2, 0.25 * pow(2, Double(failures - 1)))
    }
}
