import Foundation
import WhiteboardCore

/// Errors thrown by `WBMacOSActionItemsProvider`.
enum WBMacOSActionItemsProviderError: LocalizedError {
    /// The ingest was accepted but the stored record hadn't picked the change up before the
    /// confirmation window ran out. The change may still land after this.
    case changeNotConfirmed

    var errorDescription: String? {
        switch self {
        case .changeNotConfirmed:
            return "The change was sent but hasn't shown up yet. Try again in a moment."
        }
    }
}

/// Persists a change to a whiteboard's action items, returning the whiteboard's full item list
/// **as stored** — the call only returns once the engine has the change.
///
/// Read-only access needs no provider: action items travel inside the whiteboard record, so
/// they arrive already mapped on `WBMacOSWhiteboard.actionItems`.
protocol WBMacOSActionItemsProviding {
    func addActionItem(text: String, toWhiteboardID whiteboardID: String) async throws -> [WBMacOSActionItem]
    func updateActionItem(
        id: String,
        text: String,
        onWhiteboardID whiteboardID: String
    ) async throws -> [WBMacOSActionItem]
    func deleteActionItem(id: String, fromWhiteboardID whiteboardID: String) async throws -> [WBMacOSActionItem]
}

/// Real provider: changes the whiteboard's railengine record through Core's
/// `WBActionItemsService` — the same write path a capture takes on iOS, minus the photo
/// upload — then waits for the engine to actually store it before returning.
///
/// The wait is why every method here is slower than its Core counterpart: ingest is queued
/// (`202 Accepted`), so a write is only known to have landed once the record's stored version
/// goes up. Returning early would let the UI show a change the engine may not have taken.
struct WBMacOSActionItemsProvider: WBMacOSActionItemsProviding {
    /// How long to wait for an ingested change to show up in storage before giving up.
    private static let confirmationTimeout = Duration.seconds(10)

    /// Gap between checks while waiting for the stored version to go up.
    private static let confirmationPollInterval = Duration.milliseconds(500)

    private let actionItemsService = WBActionItemsService()
    private let recordStore = WBWhiteboardRecordStore()

    func addActionItem(text: String, toWhiteboardID whiteboardID: String) async throws -> [WBMacOSActionItem] {
        try await confirmedChange(onWhiteboardID: whiteboardID) {
            try await actionItemsService.addActionItem(text: text, toWhiteboardID: whiteboardID)
        }
    }

    func updateActionItem(
        id: String,
        text: String,
        onWhiteboardID whiteboardID: String
    ) async throws -> [WBMacOSActionItem] {
        try await confirmedChange(onWhiteboardID: whiteboardID) {
            try await actionItemsService.updateActionItem(
                id: id,
                text: text,
                onWhiteboardID: whiteboardID
            )
        }
    }

    func deleteActionItem(id: String, fromWhiteboardID whiteboardID: String) async throws -> [WBMacOSActionItem] {
        try await confirmedChange(onWhiteboardID: whiteboardID) {
            try await actionItemsService.deleteActionItem(id: id, fromWhiteboardID: whiteboardID)
        }
    }
}

private extension WBMacOSActionItemsProvider {

    /// Runs `write`, then waits until the stored record actually carries the item list it sent —
    /// returning the items **as the engine stored them**.
    ///
    /// Matched on the item list rather than a version bump. The record gains a version on every
    /// ingest, so "the version went up" only proves *some* write landed: with more than one in
    /// flight, a delete could be confirmed by the version an unrelated add produced and read back
    /// a list still holding the deleted row. Comparing the items is what confirms *this* change.
    ///
    /// Throws `changeNotConfirmed` if the expected list hasn't shown up in time. The write may
    /// still land afterwards; the caller decides how to present that (the section keeps its prompt
    /// open so the user can retry rather than being told it worked).
    func confirmedChange(
        onWhiteboardID whiteboardID: String,
        _ write: () async throws -> [WBActionItem]
    ) async throws -> [WBMacOSActionItem] {
        let expected = try await write()
        let expectedSignature = Self.signature(of: expected)

        let confirmed = await WBMacOSPoll.untilValue(
            timeout: WBMacOSActionItemsProvider.confirmationTimeout,
            interval: WBMacOSActionItemsProvider.confirmationPollInterval
        ) { () -> WBWhiteboardRecord? in
            // A failed read is "not stored yet" rather than an error — polling ends on success
            // or timeout, and a transient failure shouldn't be either.
            guard let stored = try? await recordStore.versionedRecord(id: whiteboardID) else {
                return nil
            }
            guard Self.signature(of: stored.record.actionItems) == expectedSignature else {
                WBLog.debug(
                    "⏳📤 Whiteboard \(whiteboardID) at version \(stored.version) doesn't carry the change yet"
                )
                return nil
            }
            WBLog.debug("✅📤 Whiteboard \(whiteboardID) stored the change at version \(stored.version)")
            return stored.record
        }
        guard let confirmed else {
            WBLog.warning(
                "⚠️📤 Whiteboard \(whiteboardID) hadn't stored the change after \(WBMacOSActionItemsProvider.confirmationTimeout)"
            )
            throw WBMacOSActionItemsProviderError.changeNotConfirmed
        }
        return confirmed.actionItems.map { WBMacOSWhiteboardRecordAdapter.actionItem(from: $0) }
    }

    /// Identity of an item list for comparison: each item's id **and** text, so an edit (same id,
    /// new text) is as visible as an add or a delete. Order is ignored — the engine is free to
    /// return the list in any order.
    static func signature(of items: [WBActionItem]) -> Set<String> {
        Set(items.map { "\($0.id)|\($0.text)" })
    }
}
