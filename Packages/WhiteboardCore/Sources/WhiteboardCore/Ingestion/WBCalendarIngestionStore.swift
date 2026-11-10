//
//  WBCalendarIngestionStore.swift
//  WhiteboardCore
//

import Foundation
import RailengineIngest

/// Errors thrown by `WBCalendarIngestionStore`.
public enum WBCalendarIngestionStoreError: Error, LocalizedError {
    /// No calendar-engine ingestion token is stored in the Keychain — the user must add one in Settings.
    case missingEngineToken

    public var errorDescription: String? {
        switch self {
        case .missingEngineToken:
            return "Add your calendar ingestion token in Settings to save meetings."
        }
    }
}

/// Ingestion wrapper for calendar records — the single place the app *writes* `WBCalendarRecord`s to
/// the railengine calendar engine. Mirrors `WBCalendarRecordStore` on the read side; consumers never
/// touch the RailengineIngest SDK directly. The engine environment is encoded in the ingestion token,
/// so (unlike retrieval) no engine id / API URL is needed here.
public struct WBCalendarIngestionStore: Sendable {

    public init() {}

    /// Posts the calendar record to the engine. The engine assigns its own `EventId` per ingest, so
    /// this is an **insert, not an id-keyed upsert** — re-ingesting the same meeting creates another
    /// document. Duplicate prevention is the caller's pre-check (`WBiOSMeetingSyncService`), not here.
    public func upsert(_ record: WBCalendarRecord) async throws {
        try await makeClient().upsert(record)
    }
}

private extension WBCalendarIngestionStore {

    func makeClient() throws -> RailengineIngest {
        guard let token = WBKeychainStore.readEngineTokenCalendar() else {
            throw WBCalendarIngestionStoreError.missingEngineToken
        }
        return try RailengineIngest(engineToken: token)
    }
}
