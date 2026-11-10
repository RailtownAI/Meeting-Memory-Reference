//
//  WBWhiteboardRecordStore.swift
//  WhiteboardCore
//

import Foundation
import Railengine

/// Errors thrown by `WBWhiteboardRecordStore`.
public enum WBWhiteboardRecordStoreError: Error, LocalizedError {
    /// No whiteboard-engine PAT is stored in the Keychain — the user must add one in Settings.
    case missingEnginePAT

    public var errorDescription: String? {
        switch self {
        case .missingEnginePAT:
            return "Add your whiteboard retrieval PAT in Settings to load whiteboards."
        }
    }
}

/// Retrieval wrapper for whiteboard records — the single place the app reads
/// `WBWhiteboardRecord`s from railengine (vector search + hot storage). Consumers never touch
/// the Railengine SDK directly; the engine environment comes from `WBRailengineConfig`.
public struct WBWhiteboardRecordStore: Sendable {

    /// One page of records plus the total page count reported by the engine.
    public struct Page: Sendable {
        public let items: [WBWhiteboardRecord]
        public let totalPages: Int
    }

    public init() {}

    /// Semantic search over the whiteboard vector store, most-relevant first.
    public func search(query: String) async throws -> [WBWhiteboardRecord] {
        try await makeClient().searchVectorStore(vectorStore: .VectorStore1, query: query)
    }

    /// Fetches the records for `ids`, preserving the given order. An id that resolves to no
    /// document is skipped with a warning, not surfaced as an error, so one stale id can't take
    /// down an otherwise-good result set.
    ///
    /// Each id is read by **CustomerKey** — the engine takes the CustomerKey from the record's
    /// `id`, versions the document under it on every ingest, and this query mode returns those
    /// versions newest-first, so one row is the current record. (A `$.id:` JSONPath search returns
    /// documents too, but can answer with a superseded version.)
    public func records(ids: [String]) async throws -> [WBWhiteboardRecord] {
        guard !ids.isEmpty else {
            return []
        }
        let client = try makeClient()
        return try await withThrowingTaskGroup(of: (Int, WBWhiteboardRecord?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    // Fetched by CustomerKey, not JSONPath: the engine keys each document by our
                    // record `id` as its CustomerKey, and this query mode returns that key's
                    // versions newest-first — so one row is the current record. A `$.id:` JSONPath
                    // search can answer with a superseded version (observed: v3 while v8 existed).
                    let page: StoragePage<WBWhiteboardRecord> = try await client.getStorageDocumentByCustomerKey(
                        customerKey: id,
                        options: StorageQueryOptions(pageNumber: 1, pageSize: 1)
                    )
                    return (index, page.items.first)
                }
            }
            var indexedRecords: [(index: Int, record: WBWhiteboardRecord)] = []
            for try await (index, record) in group {
                if let record {
                    indexedRecords.append((index, record))
                } else {
                    WBLog.debug("No storage document found for whiteboard record id \(ids[index])")
                }
            }
            return indexedRecords
                .sorted { $0.index < $1.index }
                .map(\.record)
        }
    }

    /// Fetches every record captured in the given meeting (`meetingId` on the wire) — the
    /// sibling set behind a detail carousel. Walks all storage pages of the JSONPath match.
    ///
    /// Content comes from a second read by CustomerKey — see `currentRecords(matchingJSONPath:)`,
    /// which is what keeps an edited capture from paging in with its pre-edit content.
    public func records(meetingID: String) async throws -> [WBWhiteboardRecord] {
        try await currentRecords(matchingJSONPath: "$.meetingId:\(meetingID)")
    }

    /// Fetches every record carrying the given `imageId` (JSONPath `$.imageId:`).
    /// The `imageId` (hex) is one of two ids minted from a photo's SHA-256; `records(ids:)` matches
    /// the sibling content `id` (GUID) instead — this is a distinct field/query.
    public func records(imageID: String) async throws -> [WBWhiteboardRecord] {
        try await currentRecords(matchingJSONPath: "$.imageId:\(imageID)")
    }

    /// The record stored under `id`, together with the engine's version number for it.
    ///
    /// The version is only on the document envelope, not in the record itself, so this reads the
    /// envelope form. It's what lets a writer confirm its change actually landed: ingest is queued
    /// (`202 Accepted`), so the way to know a write is stored is to watch the version go up.
    ///
    /// `nil` when no document matches.
    public func versionedRecord(id: String) async throws -> (record: WBWhiteboardRecord, version: Int)? {
        let page: EngineDocumentPage = try await makeClient().getStorageDocumentByCustomerKey(
            customerKey: id,
            options: StorageQueryOptions(pageNumber: 1, pageSize: 1)
        )
        guard
            let document = page.items.first,
            let record = try? JSONDecoder().decode(
                WBWhiteboardRecord.self,
                from: Data(document.content.utf8)
            )
        else {
            return nil
        }
        return (record: record, version: document.version)
    }

    /// One page of all stored whiteboard records (browse/debug surface).
    public func list(pageNumber: Int = 1, pageSize: Int = 25) async throws -> Page {
        let page: StoragePage<WBWhiteboardRecord> = try await makeClient().listStorageDocuments(
            options: StorageQueryOptions(pageNumber: pageNumber, pageSize: pageSize)
        )
        return Page(items: page.items, totalPages: page.totalPages)
    }

    /// Deletes every whiteboard record in the engine, returning the number removed.
    public func deleteAll() async throws -> Int {
        try await makeClient().deleteAllStorageDocuments()
    }
}

private extension WBWhiteboardRecordStore {

    /// The **current** version of every record matching `jsonPathQuery`.
    ///
    /// Two hops, working around a **known engine bug**: a JSONPath search is supposed to return
    /// the latest version of each matching document, but has been seen answering with a
    /// superseded one (a record read back at version 3 while version 8 was current), so an edited
    /// capture would come back with its pre-edit content. A record's `id` never changes across
    /// versions, though — so the search is used purely to discover *which* records match, and each
    /// id is then read by CustomerKey, the mode that reliably returns the current version.
    ///
    /// Costs one request per matching record on top of the search. Fine at a meeting's handful of
    /// captures, but it scales with the result set, so it is worth undoing rather than keeping.
    ///
    /// TODO: revert to the single JSONPath search once the engine returns the latest version for
    /// it. The whole body becomes the paging loop already in `recordIDs(matchingJSONPath:)` with
    /// `page.items` collected instead of just their ids, and `recordIDs` itself goes away. To check
    /// whether the fix has landed: edit a record (add an action item), then query
    /// `Storage?JsonPathQuery=$.id:<recordID>` — if it answers with the edited content rather than
    /// an older version, this hop is no longer needed.
    func currentRecords(matchingJSONPath jsonPathQuery: String) async throws -> [WBWhiteboardRecord] {
        let ids = try await recordIDs(matchingJSONPath: jsonPathQuery)
        return try await records(ids: ids)
    }

    /// The `id`s of the records matching `jsonPathQuery`, in engine order, de-duplicated. Walks
    /// every page. Only the ids are taken — the content that comes back may be a stale version.
    func recordIDs(matchingJSONPath jsonPathQuery: String) async throws -> [String] {
        let client = try makeClient()
        var ids: [String] = []
        var seen: Set<String> = []
        var pageNumber = 1
        var totalPages = 1
        while pageNumber <= totalPages {
            let page: StoragePage<WBWhiteboardRecord> = try await client.getStorageDocumentsByJsonPath(
                jsonPathQuery: jsonPathQuery,
                options: StorageQueryOptions(pageNumber: pageNumber, pageSize: 100)
            )
            for record in page.items where seen.insert(record.id).inserted {
                ids.append(record.id)
            }
            totalPages = page.totalPages
            pageNumber += 1
        }
        return ids
    }

    func makeClient() throws -> Railengine {
        guard let pat = WBKeychainStore.readEnginePATWhiteboard() else {
            throw WBWhiteboardRecordStoreError.missingEnginePAT
        }
        return try Railengine(
            pat: pat,
            engineId: WBRailengineConfig.whiteboardEngineID,
            apiUrl: WBRailengineConfig.apiURL
        )
    }
}
