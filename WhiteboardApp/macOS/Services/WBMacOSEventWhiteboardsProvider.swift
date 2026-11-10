import Foundation
import WhiteboardCore

/// Searches the captured-whiteboard knowledge base for a calendar event's captures.
///
/// Recurring events share a `calendarEventID` across every instance, so `occurrenceStart`
/// pins which occurrence's captures to resolve.
protocol WBMacOSEventWhiteboardsProviding {
    func whiteboards(
        forCalendarEventID calendarEventID: String,
        occurrenceStart: Date
    ) async throws -> [WBMacOSWhiteboard]
}

/// Real event-whiteboards provider: mints the occurrence's deterministic meeting id
/// (`<eventUID>#<startEpoch>`, the same id iOS mints at ingest) and fetches its captures
/// through the shared `WBMeetingContentLoader` — one exact lookup, no calendar-engine hop
/// and no nearest-occurrence heuristics. An event with no captures resolves to an empty
/// list — callers show their empty state.
struct WBMacOSEventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding {
    private let contentLoader = WBMeetingContentLoader()

    func whiteboards(
        forCalendarEventID calendarEventID: String,
        occurrenceStart: Date
    ) async throws -> [WBMacOSWhiteboard] {
        let meetingID = WBMeetingID.mint(
            eventUID: calendarEventID,
            startEpoch: Int(occurrenceStart.timeIntervalSince1970)
        )
        let records = try await contentLoader.recentCaptures(meetingID: meetingID)
        WBLog.debug("Event \(calendarEventID): \(records.count) capture(s) for meeting \(meetingID)")
        return records.map { WBMacOSWhiteboardRecordAdapter.whiteboard(from: $0) }
    }
}
