import Foundation
import WhiteboardCore

/// iOS-side display model for a meeting shown on the Home screen — a slimmed mapping of Core's
/// `WBCalendarEvent`, holding only what the UI needs plus the identifier used to refetch/swap.
struct WBiOSMeeting: Identifiable {
    /// Stable cross-device identifier (`calendarItemExternalIdentifier`). Non-optional here — an
    /// event without one is dropped during mapping (see `init?`).
    let calendarItemExternalIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let attendees: [WBiOSAttendee]

    /// Time range with date, e.g. "11:00AM - 12:00PM (Jul 31, 2026)". Precomputed at init using the
    /// view model's shared formatters, so it isn't rebuilt on every render.
    let timeRangeText: String

    /// Compact day + time range for the meeting row, e.g. "Today, 11:00AM - 1:00PM". Precomputed at
    /// init; the day is relative ("Today"/"Yesterday") or the date for older meetings.
    let dayTimeText: String

    /// railengine link id, resolved asynchronously after selection by `WBiOSMeetingSyncService`.
    /// `nil` until resolved.
    var meetingID: String?

    /// Unique per occurrence: the external identifier is shared across recurring occurrences, so it
    /// is paired with `start` to identify a specific one.
    var id: String {
        "\(calendarItemExternalIdentifier)@\(start.timeIntervalSince1970)"
    }

    /// Occurrence start in whole seconds since 1970 — the granularity used to mint `meetingID`.
    var startEpoch: Int {
        Int(start.timeIntervalSince1970)
    }

    /// Maps a Core `WBCalendarEvent` to the display model, or `nil` (with a warning) when the event
    /// has no external identifier — which should not happen for fetched events. The `timeFormatter`
    /// ("h:mma") and `dateFormatter` ("MMM d, yyyy") are injected so they can be shared/reused.
    init?(from event: WBCalendarEvent, timeFormatter: DateFormatter, dateFormatter: DateFormatter) {
        guard let externalIdentifier = event.externalIdentifier else {
            WBLog.warning("⚠️📅 Skipping meeting without external identifier: \(event.title)")
            return nil
        }
        self.calendarItemExternalIdentifier = externalIdentifier
        self.title = event.title
        self.start = event.startDate
        self.end = event.endDate
        self.location = event.location
        self.meetingID = nil

        let times = "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
        self.timeRangeText = "\(times) (\(dateFormatter.string(from: event.startDate)))"

        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) {
            day = "Today"
        } else if calendar.isDateInYesterday(event.startDate) {
            day = "Yesterday"
        } else {
            day = dateFormatter.string(from: event.startDate)
        }
        self.dayTimeText = "\(day), \(times)"

        // Organizer-first, person-only, de-duplicated (Core rule; reused by macOS for consistency).
        let people = WBEventAttendee.personList(organizer: event.organizer, attendees: event.attendees)
        self.attendees = people.map { person in
            // Portraits resolve in `WBiOSAttendeeView` from Contacts, keyed by email/name.
            WBiOSAttendee(
                id: person.url.absoluteString,
                name: person.displayName,
                email: person.emailAddress
            )
        }
    }
}
