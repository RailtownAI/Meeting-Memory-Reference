//
//  WBMeetingContentLoader.swift
//  WhiteboardCore
//

import Foundation

/// Loads a meeting's captured content — the whiteboard records from railengine plus their photo
/// bytes from iCloud. Shared read path for both apps (iOS Home, macOS detail); it never ingests.
///
/// Records come from `WBWhiteboardRecordStore` (keyed by `meetingId`); each record's `imageId`
/// resolves to a photo in the iCloud file store. Records and photos are fetched separately so
/// callers can load records first and stream photos in lazily.
public struct WBMeetingContentLoader: Sendable {

    private let whiteboardRecords = WBWhiteboardRecordStore()

    public init() {}

    /// Whether the iCloud container backing photo storage is currently reachable.
    public var isICloudAvailable: Bool {
        WBFileStore.isICloudAvailable
    }

    /// The whiteboard capture records for a meeting, most recent first (by capture time).
    public func recentCaptures(meetingID: String) async throws -> [WBWhiteboardRecord] {
        try await whiteboardRecords.records(meetingID: meetingID)
            .sorted { $0.capturedAtEpoch > $1.capturedAtEpoch }
    }

    /// The photo bytes for a capture's `imageId`, or `nil` when no photo is stored for it (or it
    /// hasn't downloaded from iCloud yet). Fetch lazily, per displayed capture.
    public func photoData(imageID: String) async throws -> Data? {
        try await WBFileStore.photoData(forImageID: imageID)
    }
}
