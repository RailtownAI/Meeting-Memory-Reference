import Foundation

/// A calendar meeting/event record, as stored in / exchanged with railengine.
///
/// Matches the backend contract exactly. Distinct from the on-device EventKit `WBCalendarEvent` —
/// this is the ingested/server representation, with people as **opaque references** (`organizerRef`,
/// `participantRefs`) rather than PII.
///
/// Ties to whiteboard captures via `meetingId`. `eventUID` references the calendar event; since
/// `calendarItemExternalIdentifier` is not unique for recurring meetings, a specific occurrence is
/// pinned by `eventUID` + `occurrenceStart`. Dates are kept in wire form (ISO-8601 + epoch seconds).
///
/// **Contract fidelity / sentinels.** Every property is **non-optional** to mirror the railengine
/// contract 1:1 — this model deliberately does *not* use optionals to signal "missing." Instead,
/// mapping to/from app-local models is where "missing vs. empty" is interpreted, using sentinels:
/// - `String` — an empty string (`""`) may be treated as absent (or a genuine empty value).
/// - `Array` — an empty array (`[]`) may be treated as absent.
/// - epoch `Int` (`startEpoch`/`endEpoch`) — `0` means unset.
/// - `isRecurring` — treated as `false` when not provided.
///
/// Keep this model faithful to the wire format; put any absent-value interpretation in the mapping.
public struct WBCalendarRecord: Codable, Sendable {
    /// Stable record id (e.g. "cal_01J8F3K2QX7").
    public let id: String

    /// Unique id linking this event to its whiteboard captures (`WBWhiteboardRecord.meetingId`).
    public var meetingId: String

    /// Calendar event identifier (non-unique for recurring meetings — pair with `occurrenceStart`).
    public var eventUID: String

    /// Identifier of the calendar this event belongs to.
    public var calendarId: String

    /// Event title.
    public var title: String

    /// Event description/notes.
    public var description: String

    /// Whether the event is part of a recurring series. Treated as `false` when not provided.
    public var isRecurring: Bool

    /// ISO-8601 start of this occurrence.
    public var occurrenceStart: String

    /// ISO-8601 end of this occurrence.
    public var occurrenceEnd: String

    /// Occurrence start as epoch seconds (mirrors `occurrenceStart`). `0` if unset.
    public var startEpoch: Int

    /// Occurrence end as epoch seconds (mirrors `occurrenceEnd`). `0` if unset.
    public var endEpoch: Int

    /// IANA time zone identifier (e.g. "America/Vancouver").
    public var timeZone: String

    /// Opaque reference to the organizer person.
    public var organizerRef: String

    /// Opaque references to participant persons.
    public var participantRefs: [String]

    public init(
        id: String,
        meetingId: String,
        eventUID: String,
        calendarId: String,
        title: String,
        description: String,
        isRecurring: Bool,
        occurrenceStart: String,
        occurrenceEnd: String,
        startEpoch: Int,
        endEpoch: Int,
        timeZone: String,
        organizerRef: String,
        participantRefs: [String]
    ) {
        self.id = id
        self.meetingId = meetingId
        self.eventUID = eventUID
        self.calendarId = calendarId
        self.title = title
        self.description = description
        self.isRecurring = isRecurring
        self.occurrenceStart = occurrenceStart
        self.occurrenceEnd = occurrenceEnd
        self.startEpoch = startEpoch
        self.endEpoch = endEpoch
        self.timeZone = timeZone
        self.organizerRef = organizerRef
        self.participantRefs = participantRefs
    }
}
