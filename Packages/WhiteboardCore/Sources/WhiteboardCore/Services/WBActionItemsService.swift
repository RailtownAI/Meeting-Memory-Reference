//
//  WBActionItemsService.swift
//  WhiteboardCore
//

import Foundation

/// Errors thrown by `WBActionItemsService`.
public enum WBActionItemsServiceError: Error, LocalizedError {
    /// No stored whiteboard record matches the id the caller asked to edit.
    case whiteboardNotFound(recordID: String)

    public var errorDescription: String? {
        switch self {
        case .whiteboardNotFound(let recordID):
            return "Couldn't find the stored whiteboard \(recordID) to update."
        }
    }
}

/// Adds, edits, and deletes the action items of an already-ingested whiteboard.
///
/// Action items live **inside** the whiteboard record (`WBWhiteboardRecord.actionItems`) —
/// there is no separate action-items store — so changing them is a read-modify-write of the
/// whole record: fetch it, change the items, ingest it again under the same `id`.
///
/// The write is the **same ingest iOS uses at capture time** (`WBWhiteboardIngestionStore`),
/// minus the photo upload. The engine versions documents by CustomerKey, which it takes from
/// the record's `id` — so re-ingesting an existing id adds a new version of that document
/// rather than a second document, and reads by CustomerKey return the version just written.
public struct WBActionItemsService: Sendable {

    private let records = WBWhiteboardRecordStore()
    private let ingestion = WBWhiteboardIngestionStore()

    public init() {}

    /// Appends an action item to the whiteboard's record and re-ingests it, returning the
    /// record's full item list. Blank text is rejected by the caller's prompt; a blank that
    /// slips through is dropped and the stored list comes back unchanged.
    ///
    /// The item is minted the same way a capture mints its own (`WBActionItem.make`): a
    /// fresh `UUID` and `statusUnknown`. Every item carries that status for now — the wire
    /// contract has no agreed done/open values yet, so nothing writes one.
    @discardableResult
    public func addActionItem(text: String, toWhiteboardID whiteboardID: String) async throws -> [WBActionItem] {
        guard let item = WBActionItem.make(from: [text]).first else {
            return try await actionItems(ofWhiteboardID: whiteboardID)
        }
        return try await updateActionItems(ofWhiteboardID: whiteboardID) { $0 + [item] }
    }

    /// Rewrites one action item's text, returning the record's full item list. Blank text leaves
    /// the item untouched — emptying the field is not a back door to deleting a row, which is what
    /// `deleteActionItem(id:fromWhiteboardID:)` is for. An id that matches nothing is a no-op.
    @discardableResult
    public func updateActionItem(
        id: String,
        text: String,
        onWhiteboardID whiteboardID: String
    ) async throws -> [WBActionItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await actionItems(ofWhiteboardID: whiteboardID)
        }
        return try await updateActionItems(ofWhiteboardID: whiteboardID) { items in
            items.map { item in
                guard item.id == id else {
                    return item
                }
                var edited = item
                edited.text = trimmed
                return edited
            }
        }
    }

    /// Removes one action item, returning the record's remaining items. There is no undo: the
    /// item is gone from the record on the next ingest. An id that matches nothing is a no-op.
    @discardableResult
    public func deleteActionItem(id: String, fromWhiteboardID whiteboardID: String) async throws -> [WBActionItem] {
        try await updateActionItems(ofWhiteboardID: whiteboardID) { items in
            items.filter { $0.id != id }
        }
    }
}

private extension WBActionItemsService {

    /// The stored record's action items, for the paths that change nothing.
    func actionItems(ofWhiteboardID whiteboardID: String) async throws -> [WBActionItem] {
        try await storedRecord(whiteboardID: whiteboardID).actionItems
    }

    func storedRecord(whiteboardID: String) async throws -> WBWhiteboardRecord {
        guard let stored = try await records.records(ids: [whiteboardID]).first else {
            throw WBActionItemsServiceError.whiteboardNotFound(recordID: whiteboardID)
        }
        return stored
    }

    /// Reads the record, applies `transform` to its action items, and re-ingests it — the one
    /// read-modify-write every mutation goes through, so they can't drift apart in how they
    /// resolve the record or write it back.
    func updateActionItems(
        ofWhiteboardID whiteboardID: String,
        transform: ([WBActionItem]) -> [WBActionItem]
    ) async throws -> [WBActionItem] {
        let stored = try await storedRecord(whiteboardID: whiteboardID)
        let record: WBWhiteboardRecord = {
            var updated = stored
            updated.actionItems = transform(stored.actionItems)
            return updated
        }()

        WBLog.debug("📤 Re-ingesting whiteboard \(whiteboardID) with \(record.actionItems.count) action item(s)")
        do {
            try await ingestion.upsert(record)
        } catch {
            WBLog.error("⚠️📤 Ingest failed for whiteboard \(whiteboardID): \(error)")
            throw error
        }
        // Ingest is queued (`202 Accepted`), so the change isn't readable yet when this returns.
        // Callers that need to show only stored state confirm it themselves — see
        // `WBMacOSActionItemsProvider`, which polls `versionedRecord(id:)` for the version bump.
        return record.actionItems
    }
}
