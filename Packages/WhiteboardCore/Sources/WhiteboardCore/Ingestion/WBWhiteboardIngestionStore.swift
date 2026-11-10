//
//  WBWhiteboardIngestionStore.swift
//  WhiteboardCore
//

import Foundation
import RailengineIngest

/// Errors thrown by `WBWhiteboardIngestionStore`.
public enum WBWhiteboardIngestionStoreError: Error, LocalizedError {
    /// No whiteboard-engine ingestion token is stored in the Keychain — the user must add one in Settings.
    case missingEngineToken

    public var errorDescription: String? {
        switch self {
        case .missingEngineToken:
            return "Add your whiteboard ingestion token in Settings to save whiteboards."
        }
    }
}

/// Ingestion wrapper for whiteboard records — the single place the app *writes* `WBWhiteboardRecord`s
/// to the railengine whiteboard engine. Mirrors `WBWhiteboardRecordStore` on the read side; the
/// engine environment is encoded in the ingestion token.
public struct WBWhiteboardIngestionStore: Sendable {

    public init() {}

    /// Posts the whiteboard record to the engine. The engine versions documents by **CustomerKey**,
    /// which it takes from the record's own `id`: re-ingesting an id that already exists creates a
    /// **new version** of that document rather than a second document, which is what lets a record
    /// be edited after capture (`WBActionItemsService`). A capture mints a fresh id per photo, so
    /// distinct captures never collide. The engine's own `eventId` is per-version and unrelated to
    /// our `id`, so a record can't be fetched by it — read by CustomerKey instead.
    ///
    /// Ingest is queued server-side (the API answers `202 Accepted`), so a new version can take a
    /// few seconds to become readable.
    public func upsert(_ record: WBWhiteboardRecord) async throws {
        try await makeClient().upsert(record)
    }
}

private extension WBWhiteboardIngestionStore {

    func makeClient() throws -> RailengineIngest {
        guard let token = WBKeychainStore.readEngineTokenWhiteboard() else {
            throw WBWhiteboardIngestionStoreError.missingEngineToken
        }
        return try RailengineIngest(engineToken: token)
    }
}
