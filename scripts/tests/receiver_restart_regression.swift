import Foundation

@main struct ReceiverRestartRegression {
    static func main() {
        var policy = ReceiverRestartBudget()
        let begin = Date(timeIntervalSinceReferenceDate: 1000)
        for attempt in 1...6 {
            let time = begin.addingTimeInterval(Double(attempt))
            policy.didStart(now: time)
            let delay = policy.retryDelayAfterExit(now: time.addingTimeInterval(0.1))
            precondition((delay == nil) == (attempt == 6), "Repeated launches must not reset failure count")
            if let delay { precondition(delay >= 0.25 && delay <= 2) }
        }
        policy.didStart(now: begin.addingTimeInterval(10))
        precondition(policy.retryDelayAfterExit(now: begin.addingTimeInterval(41)) == 0.25,
                     "A stable process must recover its retry budget")
        policy.reset()
        precondition(policy.failures == 0)
        precondition(policy.retryDelayAfterExit(now: begin) == 0.25)
        print("PASS: bounded retries, exponential backoff, stable-run recovery and explicit reset")
    }
}
