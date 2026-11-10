import Foundation
import WhiteboardCore

/// Fetches every whiteboard captured in a meeting (the records sharing its `meetingID`) —
/// the sibling set the detail carousel pages.
///
/// Returns an empty array when the meeting has no stored captures — callers fall back to
/// what they already have.
protocol WBMacOSMeetingWhiteboardsProviding {
    func whiteboards(forMeetingID meetingID: String) async throws -> [WBMacOSWhiteboard]

    /// One whiteboard, read straight from storage by its id. `nil` when it no longer exists.
    func whiteboard(forWhiteboardID whiteboardID: String) async throws -> WBMacOSWhiteboard?
}

/// Real provider: fetches the meeting's captures through the shared `WBMeetingContentLoader`
/// (the same read path iOS Home uses, latest capture first) and adapts them to app-local
/// models at the provider layer.
struct WBMacOSMeetingWhiteboardsProvider: WBMacOSMeetingWhiteboardsProviding {
    private let contentLoader = WBMeetingContentLoader()
    private let recordStore = WBWhiteboardRecordStore()

    func whiteboards(forMeetingID meetingID: String) async throws -> [WBMacOSWhiteboard] {
        let records = try await contentLoader.recentCaptures(meetingID: meetingID)
        return records.map { WBMacOSWhiteboardRecordAdapter.whiteboard(from: $0) }
    }

    /// Read by id, which the record store resolves through the engine's CustomerKey lookup — the
    /// query mode that answers with the record's current version.
    func whiteboard(forWhiteboardID whiteboardID: String) async throws -> WBMacOSWhiteboard? {
        try await recordStore.records(ids: [whiteboardID])
            .first
            .map { WBMacOSWhiteboardRecordAdapter.whiteboard(from: $0) }
    }
}
