import Foundation
import Observation

/// Owns the meeting-centric fetches behind the detail column: the personal calendar data
/// (title, times, attendees) for a calendar event id, and the meeting's full capture set
/// (the carousel's sibling whiteboards). Results are cached so each meeting is fetched once;
/// both providers swap at the composition root without changes here or in the view models.
@Observable
final class WBMacOSMeetingDetailManager {

    private let meetingDetailProvider: WBMacOSMeetingDetailProviding
    private let meetingWhiteboardsProvider: WBMacOSMeetingWhiteboardsProviding
    private var detailByEventID: [String: WBMacOSMeetingDetail] = [:]
    private var whiteboardsByMeetingID: [String: [WBMacOSWhiteboard]] = [:]

    init(
        meetingDetailProvider: WBMacOSMeetingDetailProviding,
        meetingWhiteboardsProvider: WBMacOSMeetingWhiteboardsProviding
    ) {
        self.meetingDetailProvider = meetingDetailProvider
        self.meetingWhiteboardsProvider = meetingWhiteboardsProvider
    }

    func detail(
        forCalendarEventID calendarEventID: String?,
        occurrenceStart: Date?
    ) -> WBMacOSMeetingDetail? {
        guard let calendarEventID else {
            return nil
        }
        return detailByEventID[Self.cacheKey(calendarEventID, occurrenceStart)]
    }

    /// A failed or unresolvable lookup simply leaves the detail absent — consumers degrade
    /// gracefully (no meeting card, no attendees, date-only subtitle).
    func loadDetail(
        forCalendarEventID calendarEventID: String?,
        occurrenceStart: Date?
    ) async {
        guard let calendarEventID else {
            return
        }
        let cacheKey = Self.cacheKey(calendarEventID, occurrenceStart)
        guard detailByEventID[cacheKey] == nil else {
            return
        }
        let detail = try? await meetingDetailProvider.meetingDetail(
            forCalendarEventID: calendarEventID,
            occurrenceStart: occurrenceStart
        )
        guard !Task.isCancelled else {
            return
        }
        if let detail {
            detailByEventID[cacheKey] = detail
        }
    }

    /// Re-reads one whiteboard from storage and adopts it into the cached capture sets,
    /// returning it. `nil` when it can't be read, leaving the caches as they were.
    ///
    /// The detail calls this whenever a whiteboard is opened, because what it was handed may be
    /// stale: a search answer carries the record as the vector store had it, and a cached capture
    /// set was fetched once. Reading by id goes through the engine's CustomerKey lookup, which
    /// answers with the record's current version.
    @discardableResult
    func refreshWhiteboard(id whiteboardID: String) async -> WBMacOSWhiteboard? {
        guard
            let refreshed = try? await meetingWhiteboardsProvider.whiteboard(
                forWhiteboardID: whiteboardID
            )
        else {
            return nil
        }
        for (meetingID, whiteboards) in whiteboardsByMeetingID
        where whiteboards.contains(where: { $0.id == whiteboardID }) {
            whiteboardsByMeetingID[meetingID] = whiteboards.map { whiteboard in
                whiteboard.id == whiteboardID ? refreshed : whiteboard
            }
        }
        return refreshed
    }

    /// Replaces a whiteboard's action items everywhere the capture sets hold it.
    ///
    /// The cache is what the detail rebuilds from, so without this a change stored from the
    /// action-items section would be undone on screen the next time the section was rebuilt —
    /// it would re-read the pre-change list from here.
    func updateActionItems(_ items: [WBMacOSActionItem], forWhiteboardID whiteboardID: String) {
        for (meetingID, whiteboards) in whiteboardsByMeetingID
        where whiteboards.contains(where: { $0.id == whiteboardID }) {
            whiteboardsByMeetingID[meetingID] = whiteboards.map { whiteboard in
                guard whiteboard.id == whiteboardID else {
                    return whiteboard
                }
                var updated = whiteboard
                updated.actionItems = items
                return updated
            }
        }
    }

    /// Recurring events share a `calendarEventID`, so the cache is keyed per occurrence.
    private static func cacheKey(_ calendarEventID: String, _ occurrenceStart: Date?) -> String {
        guard let occurrenceStart else {
            return calendarEventID
        }
        return "\(calendarEventID)|\(occurrenceStart.timeIntervalSince1970)"
    }

    /// The meeting's fetched capture set, or `nil` while unloaded — consumers fall back to
    /// the whiteboards they already carry.
    func whiteboards(forMeetingID meetingID: String?) -> [WBMacOSWhiteboard]? {
        guard let meetingID else {
            return nil
        }
        return whiteboardsByMeetingID[meetingID]
    }

    /// A failed or empty fetch simply leaves the set absent — consumers keep their fallback,
    /// and the next selection of the meeting retries.
    func loadWhiteboards(forMeetingID meetingID: String?) async {
        guard let meetingID else {
            return
        }
        guard whiteboardsByMeetingID[meetingID] == nil else {
            return
        }
        let whiteboards = try? await meetingWhiteboardsProvider.whiteboards(
            forMeetingID: meetingID
        )
        guard !Task.isCancelled else {
            return
        }
        if let whiteboards, !whiteboards.isEmpty {
            whiteboardsByMeetingID[meetingID] = whiteboards
        }
    }
}
