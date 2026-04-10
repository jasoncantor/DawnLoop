import Foundation

/// Broadcasts one eventual result to every caller that joined while work was in flight.
/// This prevents re-entrant `withCheckedContinuation` calls from overwriting an earlier waiter.
@MainActor
final class PendingCheckedContinuations<Value> {
    private var continuations: [CheckedContinuation<Value, Never>] = []

    func add(_ continuation: CheckedContinuation<Value, Never>) -> Bool {
        let shouldStartWork = continuations.isEmpty
        continuations.append(continuation)
        return shouldStartWork
    }

    func resumeAll(returning value: Value) {
        let waiters = continuations
        continuations = []
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }
}
