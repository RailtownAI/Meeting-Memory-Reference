//
//  WBWhiteboardSaveService.swift
//  WhiteboardCore
//

import Foundation

/// Saves a captured whiteboard: upload the photo to iCloud, then ingest a record into railengine.
/// The single write-path for whiteboard captures (composes `WBFileStore` +
/// `WBWhiteboardIngestionStore`).
///
/// Identity is a fresh `UUID` (see `makeIDs`) used as **both** the record `id` and the iCloud photo
/// filename (`imageId`). This is deliberately *non-deterministic*: processing the same photo again in
/// a new capture mints new ids, uploads a new copy to iCloud, and ingests a new record — so the same
/// whiteboard photo can be attached to multiple meetings. `id` is a UUID because railengine's
/// `eventId` must parse as one. There is intentionally **no dedup**: every capture is distinct.
///
/// Mint the ids **once per capture** (`makeIDs()`) and reuse them across retries: because the photo
/// is only uploaded when it isn't already in iCloud, a retry after a failed ingest re-ingests without
/// re-uploading.
///
/// Pipeline (given ids minted by the caller):
/// 1. upload the photo to iCloud under `imageId` — unless it's already there (retry)
/// 2. ingest the record into railengine
public struct WBWhiteboardSaveService: Sendable {

    private let ingestion = WBWhiteboardIngestionStore()

    public init() {}

    /// Mints a fresh capture identity: one `UUID` used as **both** the record `id` (railengine's
    /// `eventId` must parse as a UUID) and the iCloud filename (`imageID`). Non-deterministic by
    /// design — each capture is distinct, so the same photo can be saved to multiple meetings. Call
    /// **once per capture** and hold the result, so a retry passes the same ids and skips re-upload.
    public static func makeIDs() -> (id: String, imageID: String) {
        let uuid = UUID().uuidString
        return (id: uuid, imageID: uuid)
    }

    /// Uploads the photo (unless iCloud already holds it) and ingests the record. `id`/`imageID` come
    /// from `makeIDs()`, minted once per capture so a retry after a failed ingest reuses them and
    /// doesn't re-upload the photo.
    ///
    /// Returns the record as ingested. Ingest is queued (`202 Accepted`), so a read right after this
    /// can miss the record; callers that need it straight away (Spotlight, App Intents) use this
    /// value instead of fetching it back.
    @discardableResult
    public func save(
        imageData: Data,
        id: String,
        imageID: String,
        title: String,
        summary: String,
        ocrText: String,
        actionItems: [WBActionItem],
        meetingID: String,
        eventUID: String,
        occurrenceStart: Date,
        capturedByDevice: String
    ) async throws -> WBWhiteboardRecord {
        // Skip the upload when the photo is already in iCloud — this is what lets a retry after a
        // failed ingest re-ingest without re-uploading (the ids are stable across a capture's retries).
        let iCloudHasPhoto = (try? WBFileStore.photoExists(imageID: imageID)) ?? false
        if iCloudHasPhoto {
            WBLog.debug("☁️📤 Photo already in iCloud (\(imageID)) — skipping upload")
        } else {
            WBLog.debug("☁️📤 Starting iCloud upload for \(imageID)")
            try WBFileStore.uploadPhotoData(imageData, imageID: imageID)
            WBLog.debug("☁️📤 iCloud upload complete for \(imageID)")
        }

        let record = Self.makeRecord(
            id: id,
            imageID: imageID,
            title: title,
            summary: summary,
            ocrText: ocrText,
            actionItems: actionItems,
            meetingID: meetingID,
            eventUID: eventUID,
            occurrenceStart: occurrenceStart,
            capturedByDevice: capturedByDevice
        )
        WBLog.trace("🧾 Ingesting WBWhiteboardRecord: \(record)")
        WBLog.debug("📤 Starting ingest for \(id)")
        try await ingestion.upsert(record)
        WBLog.debug("📤 Ingest complete for \(id)")
        return record
    }
}

private extension WBWhiteboardSaveService {

    static func makeRecord(
        id: String,
        imageID: String,
        title: String,
        summary: String,
        ocrText: String,
        actionItems: [WBActionItem],
        meetingID: String,
        eventUID: String,
        occurrenceStart: Date,
        capturedByDevice: String
    ) -> WBWhiteboardRecord {
        let iso = ISO8601DateFormatter()
        let now = Date()
        return WBWhiteboardRecord(
            id: id,
            kind: "whiteboard",
            meetingId: meetingID,
            eventUID: eventUID,
            occurrenceStart: iso.string(from: occurrenceStart),
            capturedAt: iso.string(from: now),
            capturedAtEpoch: Int(now.timeIntervalSince1970),
            title: title,
            summary: summary,
            markdown: "",
            ocrText: ocrText,
            keywords: [],
            actionItems: actionItems,
            imageId: imageID,
            capturedByDevice: capturedByDevice
        )
    }
}
