import Foundation

/// Waits for something to become true on a system that won't tell us when it does.
///
/// railengine's ingest is queued — the API answers `202 Accepted` and the document appears a few
/// seconds later — so the only way to know a write landed is to look again until it has. This is
/// that shape, kept in one place so every caller waits the same way instead of hand-rolling a
/// sleep loop.
enum WBMacOSPoll {

    /// Runs `check` every `interval` until it returns a value, giving up after `timeout`.
    ///
    /// Returns the first non-`nil` value, or `nil` if the timeout passes without one. The first
    /// check happens *after* one interval, since callers poll right after doing the thing they're
    /// waiting on and an immediate look would only ever miss.
    ///
    /// `check` decides what counts as done — returning `nil` means "not yet". It should swallow
    /// its own transient failures (a failed read is "not yet", not an error), because polling
    /// stops only on success or timeout.
    static func untilValue<Value>(
        timeout: Duration,
        interval: Duration,
        check: () async -> Value?
    ) async -> Value? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try? await Task.sleep(for: interval)
            if let value = await check() {
                return value
            }
            guard ContinuousClock.now < deadline else {
                return nil
            }
        }
    }
}
