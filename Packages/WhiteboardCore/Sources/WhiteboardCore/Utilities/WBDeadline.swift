//
//  WBDeadline.swift
//  WhiteboardCore
//

import Foundation
import Synchronization

/// Thrown by `withDeadline` when the operation is still running after the deadline.
public struct WBDeadlineExceeded: Error, Sendable {
    public init() {}
}

/// Returns `operation`'s result, or throws `WBDeadlineExceeded` after `seconds`, whichever comes
/// first.
///
/// Unstructured on purpose. A task-group race waits for every child before it returns, so an
/// operation that ignores cancellation would hold the caller past the deadline. Here the operation
/// runs in its own task and is abandoned on timeout. With `cancelsOnTimeout` it is also cancelled;
/// leave that off for work that should still finish, such as a save that is already uploading.
///
/// When the caller is cancelled, this throws `CancellationError` and always cancels the operation,
/// whatever `cancelsOnTimeout` says: the flag is about the deadline only. A caller that is already
/// cancelled never starts the operation.
public func withDeadline<T: Sendable>(
    seconds: Double,
    cancelsOnTimeout: Bool = true,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = WBDeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard race.install(continuation) else {
                return
            }
            let work = Task {
                do {
                    race.finish(.success(try await operation()))
                } catch {
                    race.finish(.failure(error))
                }
            }
            let timer = Task {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    // Cancelled because the race is over: nothing left to time.
                    return
                }
                race.finish(.failure(WBDeadlineExceeded()), cancelsWork: cancelsOnTimeout)
            }
            race.track(work: work, timer: timer)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()), cancelsWork: true)
    }
}

/// First result wins; later ones are dropped. The winner also stops the timer, so it does not sleep
/// out the deadline, and cancels the work when asked to.
private final class WBDeadlineRace<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, Error>?
        var early: Result<T, Error>?
        var isFinished = false
        var cancelsWork = false
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
    }

    /// What the winning result takes out of the state, to act on outside the lock.
    private struct Won {
        let continuation: CheckedContinuation<T, Error>?
        let work: Task<Void, Never>?
        let timer: Task<Void, Never>?
    }

    private let state = Mutex(State())

    /// Takes the continuation. Returns false when the race finished before it started (the caller
    /// was already cancelled): the continuation is resumed here, and there is nothing to run.
    func install(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        let pending: Result<T, Error>? = state.withLock { state in
            if let early = state.early {
                state.early = nil
                return early
            }
            state.continuation = continuation
            return nil
        }
        guard let pending else {
            return true
        }
        continuation.resume(with: pending)
        return false
    }

    /// Keeps the two tasks so the winner can stop them. When the race is already over, stops them
    /// now.
    func track(work: Task<Void, Never>, timer: Task<Void, Never>) {
        let cancelsWork: Bool? = state.withLock { state in
            if state.isFinished {
                return state.cancelsWork
            }
            state.work = work
            state.timer = timer
            return nil
        }
        guard let cancelsWork else {
            return
        }
        timer.cancel()
        if cancelsWork {
            work.cancel()
        }
    }

    func finish(_ result: Result<T, Error>, cancelsWork: Bool = false) {
        let won: Won? = state.withLock { state in
            guard !state.isFinished else {
                return nil
            }
            state.isFinished = true
            state.cancelsWork = cancelsWork
            let won = Won(continuation: state.continuation, work: state.work, timer: state.timer)
            state.continuation = nil
            state.work = nil
            state.timer = nil
            if won.continuation == nil {
                state.early = result
            }
            return won
        }
        guard let won else {
            return
        }
        won.timer?.cancel()
        if cancelsWork {
            won.work?.cancel()
        }
        won.continuation?.resume(with: result)
    }
}
