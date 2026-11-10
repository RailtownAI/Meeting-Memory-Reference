import Foundation

/// A whiteboard capture record, as stored in / exchanged with railengine.
///
/// Matches the backend contract exactly. Dates are kept in their **wire forms** — ISO-8601 strings
/// (`occurrenceStart`, `capturedAt`) plus epoch seconds (`capturedAtEpoch`) — so this DTO decodes
/// with any `JSONDecoder`; app-local models convert to `Date` as needed.
///
/// Ties to its calendar event via `meetingId`. `eventUID` references the calendar event; since
/// `calendarItemExternalIdentifier` is not unique for recurring meetings, a specific occurrence is
/// pinned by `eventUID` + `occurrenceStart`.
///
/// **Contract fidelity / sentinels.** Every property is **non-optional** to mirror the railengine
/// contract 1:1 — this model deliberately does *not* use optionals to signal "missing." Instead,
/// mapping to/from app-local models is where "missing vs. empty" is interpreted, using sentinels:
/// - `String` — an empty string (`""`) may be treated as absent (or a genuine empty value).
/// - `Array` — an empty array (`[]`) may be treated as absent.
/// - epoch `Int` (`capturedAtEpoch`) — `0` means unset.
///
/// Keep this model faithful to the wire format; put any absent-value interpretation in the mapping.
public struct WBWhiteboardRecord: Codable, Sendable {
    /// Stable record id (e.g. "wb_01J8F3K2QX7").
    public let id: String

    /// Record kind (e.g. "whiteboard").
    public var kind: String

    /// Unique id linking this record to its calendar event (`WBCalendarRecord.meetingId`).
    public var meetingId: String

    /// Calendar event identifier (non-unique for recurring meetings — pair with `occurrenceStart`).
    public var eventUID: String

    /// ISO-8601 start of the specific meeting occurrence this capture belongs to.
    public var occurrenceStart: String

    /// ISO-8601 time the photo was captured.
    public var capturedAt: String

    /// Capture time as epoch seconds (mirrors `capturedAt`). `0` if unset.
    public var capturedAtEpoch: Int

    /// Whiteboard title (LLM-generated from the captured image).
    public var title: String

    /// Natural-language summary of the whiteboard content.
    public var summary: String

    /// Markdown rendering of the whiteboard content.
    public var markdown: String

    /// Raw OCR text extracted from the photo.
    public var ocrText: String

    /// Keywords extracted from the capture.
    public var keywords: [String]

    /// Action items extracted from the capture.
    public var actionItems: [WBActionItem]

    /// Reference to the stored image — the binary lives in iCloud; this is the id.
    public var imageId: String

    /// Identifier of the device that captured the photo.
    public var capturedByDevice: String

    public init(
        id: String,
        kind: String,
        meetingId: String,
        eventUID: String,
        occurrenceStart: String,
        capturedAt: String,
        capturedAtEpoch: Int,
        title: String,
        summary: String,
        markdown: String,
        ocrText: String,
        keywords: [String],
        actionItems: [WBActionItem],
        imageId: String,
        capturedByDevice: String
    ) {
        self.id = id
        self.kind = kind
        self.meetingId = meetingId
        self.eventUID = eventUID
        self.occurrenceStart = occurrenceStart
        self.capturedAt = capturedAt
        self.capturedAtEpoch = capturedAtEpoch
        self.title = title
        self.summary = summary
        self.markdown = markdown
        self.ocrText = ocrText
        self.keywords = keywords
        self.actionItems = actionItems
        self.imageId = imageId
        self.capturedByDevice = capturedByDevice
    }
}
