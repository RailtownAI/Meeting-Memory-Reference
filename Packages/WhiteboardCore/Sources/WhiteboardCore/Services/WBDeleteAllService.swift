//
//  WBDeleteAllService.swift
//  WhiteboardCore
//

import Foundation
import Railengine

/// Per-store counts (and any errors) from a delete-all run.
public struct WBDeleteAllResult: Sendable {
    public var whiteboardRecordsDeleted = 0
    public var calendarRecordsDeleted = 0
    public var photosDeleted = 0
    public var errors: [String] = []

    public init() {}
}

/// Deletes all of the app's stored data: whiteboard + calendar railengine records and all iCloud
/// photos. **The device's Apple Calendar (EventKit) is never touched** — this only clears the app's
/// own stores. Best-effort: each store is attempted independently, so one failure doesn't block the
/// others; per-store counts and any errors are returned.
public struct WBDeleteAllService: Sendable {

    private let whiteboardRecords = WBWhiteboardRecordStore()
    private let calendarRecords = WBCalendarRecordStore()

    public init() {}

    public func deleteAll() async -> WBDeleteAllResult {
        var result = WBDeleteAllResult()
        do {
            WBLog.debug("🗑️ Now deleting records under whiteboard rail engine")
            result.whiteboardRecordsDeleted = try await whiteboardRecords.deleteAll()
        } catch let WBEngineDeleteError.someFailed(deleted, failed) {
            result.whiteboardRecordsDeleted = deleted
            result.errors.append("Whiteboard records: \(failed) failed to delete")
        } catch {
            result.errors.append("Whiteboard records: \(error)")
        }
        do {
            WBLog.debug("🗑️ Now deleting records under calendar rail engine")
            result.calendarRecordsDeleted = try await calendarRecords.deleteAll()
        } catch let WBEngineDeleteError.someFailed(deleted, failed) {
            result.calendarRecordsDeleted = deleted
            result.errors.append("Calendar records: \(failed) failed to delete")
        } catch {
            result.errors.append("Calendar records: \(error)")
        }
        do {
            WBLog.debug("🗑️ Now deleting photos from iCloud")
            result.photosDeleted = try WBFileStore.deleteAllPhotos()
        } catch {
            result.errors.append("iCloud photos: \(error)")
        }
        return result
    }
}

/// Signals that a per-engine delete finished with some documents deleted and some failed — lets the
/// caller report the truthful success count instead of treating the whole run as a failure.
enum WBEngineDeleteError: Error {
    case someFailed(deleted: Int, failed: Int)
}

extension Railengine {
    /// Deletes every storage document in this engine, returning the number removed. Collects all
    /// event ids first (paged), then deletes each best-effort — a failed delete is counted, not
    /// fatal; if any failed it throws `.someFailed(deleted:failed:)` carrying the success count.
    func deleteAllStorageDocuments() async throws -> Int {
        var eventIds: [String] = []
        var pageNumber = 1
        var totalPages = 1
        while pageNumber <= totalPages {
            let page: EngineDocumentPage = try await listStorageDocuments(
                options: StorageQueryOptions(pageNumber: pageNumber, pageSize: 100)
            )
            totalPages = page.totalPages
            eventIds.append(contentsOf: page.items.map(\.eventId))
            pageNumber += 1
        }
        let ids = eventIds
        WBLog.debug("🗑️ Found \(ids.count) storage documents to delete: \(ids)")
        var deleted = 0
        var failed = 0
        for eventId in ids {
            do {
                try await deleteEvent(eventId: eventId)
                deleted += 1
            } catch {
                failed += 1
                let description = "\(error)"
                WBLog.error("🗑️ Failed to delete \(eventId): \(description)")
            }
        }
        if failed > 0 {
            throw WBEngineDeleteError.someFailed(deleted: deleted, failed: failed)
        }
        return deleted
    }
}
