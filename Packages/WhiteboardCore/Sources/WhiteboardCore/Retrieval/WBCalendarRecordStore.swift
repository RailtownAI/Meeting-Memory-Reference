//
//  WBCalendarRecordStore.swift
//  WhiteboardCore
//

import Foundation
import Railengine

/// Errors thrown by `WBCalendarRecordStore`.
public enum WBCalendarRecordStoreError: Error, LocalizedError {
    /// No calendar-engine PAT is stored in the Keychain — the user must add one in Settings.
    case missingEnginePAT

    public var errorDescription: String? {
        switch self {
        case .missingEnginePAT:
            return "Add your calendar retrieval PAT in Settings to load meetings."
        }
    }
}

/// Retrieval wrapper for calendar records — the single place the app reads
/// `WBCalendarRecord`s from the railengine calendar engine. Consumers never touch the
/// Railengine SDK directly; the engine environment comes from `WBRailengineConfig`.
///
/// These are the server-side, PII-free event representations (opaque `organizerRef` /
/// `participantRefs`); personal details are always re-resolved on-device via EventKit.
public struct WBCalendarRecordStore: Sendable {

    /// One page of records plus the total page count reported by the engine.
    public struct Page: Sendable {
        public let items: [WBCalendarRecord]
        public let totalPages: Int
    }

    public init() {}

    /// The calendar record for a meeting (the `meetingId` shared with its whiteboard records),
    /// or `nil` when the meeting was never ingested.
    public func record(meetingID: String) async throws -> WBCalendarRecord? {
        let page: StoragePage<WBCalendarRecord> = try await makeClient().getStorageDocumentsByJsonPath(
            jsonPathQuery: "$.meetingId:\(meetingID)",
            options: StorageQueryOptions(pageNumber: 1, pageSize: 1)
        )
        return page.items.first
    }

    /// One page of all stored calendar records (browse/debug surface).
    public func list(pageNumber: Int = 1, pageSize: Int = 25) async throws -> Page {
        let page: StoragePage<WBCalendarRecord> = try await makeClient().listStorageDocuments(
            options: StorageQueryOptions(pageNumber: pageNumber, pageSize: pageSize)
        )
        return Page(items: page.items, totalPages: page.totalPages)
    }

    /// Deletes every calendar record in the engine, returning the number removed.
    public func deleteAll() async throws -> Int {
        try await makeClient().deleteAllStorageDocuments()
    }
}

private extension WBCalendarRecordStore {

    func makeClient() throws -> Railengine {
        guard let pat = WBKeychainStore.readEnginePATCalendar() else {
            throw WBCalendarRecordStoreError.missingEnginePAT
        }
        return try Railengine(
            pat: pat,
            engineId: WBRailengineConfig.calendarEngineID,
            apiUrl: WBRailengineConfig.apiURL
        )
    }
}
