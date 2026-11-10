import Foundation
import WhiteboardCore

/// Adapts railengine wire records to app-local models — the provider layer's single mapping
/// point, shared by every provider that turns `WBWhiteboardRecord`s into UI models.
enum WBMacOSWhiteboardRecordAdapter {

    /// Adapts a wire record to the app-local model, interpreting wire sentinels
    /// (empty string, epoch `0`) as absent.
    static func whiteboard(from record: WBWhiteboardRecord) -> WBMacOSWhiteboard {
        WBMacOSWhiteboard(
            id: record.id,
            title: record.title,
            capturedAt: date(iso8601String: record.capturedAt, epochSeconds: record.capturedAtEpoch),
            occurrenceStart: optionalDate(iso8601String: record.occurrenceStart),
            summary: record.summary,
            ocrText: record.ocrText,
            imageID: record.imageId.isEmpty ? nil : record.imageId,
            meetingID: record.meetingId.isEmpty ? nil : record.meetingId,
            calendarEventID: record.eventUID.isEmpty ? nil : record.eventUID,
            actionItems: record.actionItems.map(actionItem(from:))
        )
    }

    /// Wire item → app-local item. A capture ingests every item as `statusUnknown` (a board
    /// records the task, not whether it's done), so anything but that reads as done.
    static func actionItem(from item: WBActionItem) -> WBMacOSActionItem {
        WBMacOSActionItem(
            id: item.id,
            text: item.text,
            isDone: item.status != WBActionItem.statusUnknown
        )
    }

    /// One related meeting per distinct `meetingId`, keeping the records' most-relevant-first
    /// order. Titles come straight from the records for now — resolving personal details through
    /// EventKit is deliberately deferred to the provider-swap issue.
    static func relatedMeetings(from records: [WBWhiteboardRecord]) -> [WBMacOSRelatedMeeting] {
        var seenMeetingIDs = Set<String>()
        var meetings: [WBMacOSRelatedMeeting] = []
        for record in records where !record.meetingId.isEmpty {
            guard seenMeetingIDs.insert(record.meetingId).inserted else {
                continue
            }
            meetings.append(
                WBMacOSRelatedMeeting(
                    id: record.meetingId,
                    title: record.title,
                    startDate: date(
                        iso8601String: record.occurrenceStart,
                        epochSeconds: record.capturedAtEpoch
                    ),
                    calendarEventID: record.eventUID.isEmpty ? nil : record.eventUID
                )
            )
        }
        return meetings
    }

    /// Wire date → optional `Date`: the empty-string sentinel (and anything unparseable)
    /// maps to `nil` rather than a fallback value.
    static func optionalDate(iso8601String: String) -> Date? {
        guard !iso8601String.isEmpty else {
            return nil
        }
        let plainFormatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plainFormatter.date(from: iso8601String)
            ?? fractionalFormatter.date(from: iso8601String)
    }

    /// Wire date → `Date`: the ISO-8601 string first (with or without fractional seconds),
    /// epoch seconds as fallback, `.now` as a last resort so the non-optional UI dates never
    /// depend on a malformed record.
    static func date(iso8601String: String, epochSeconds: Int) -> Date {
        let plainFormatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = plainFormatter.date(from: iso8601String)
            ?? fractionalFormatter.date(from: iso8601String) {
            return date
        }
        if epochSeconds > 0 {
            return Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        }
        return .now
    }
}
