import Foundation

/// A whiteboard capture as the macOS UI displays it.
///
/// App-local model: views never touch `WBCoreModel` types. The `WBCoreModel` → local mapping
/// happens behind the providers and is a separate issue (#12).
struct WBMacOSWhiteboard: Identifiable, Hashable {
    let id: String
    let title: String
    let capturedAt: Date

    /// Start of the specific meeting occurrence this capture belongs to — recurring events
    /// share a `calendarEventID`, so this pins which instance of the series to resolve.
    let occurrenceStart: Date?

    let summary: String

    /// Raw text lifted from the photo at capture time. Legitimately empty for a whiteboard
    /// with no legible text (a diagram), so an empty string is a result, not a failure.
    let ocrText: String

    /// Image id for the capture's photo — the provider resolves it to its binary
    /// (adapter-mapped from the record's `imageId`). One photo per record; a meeting's
    /// other shots are sibling records sharing `meetingID`.
    let imageID: String?

    /// Groups this capture with the meeting's other captures and its calendar record
    /// (`meetingId` on the wire).
    let meetingID: String?

    /// EventKit `calendarItemExternalIdentifier`, used to re-fetch personal meeting details
    /// (title, attendees) on-device — they deliberately never travel through railengine.
    let calendarEventID: String?

    /// The tasks this capture recorded. They travel inside the whiteboard record, so they
    /// arrive with it — no separate fetch. Mutable so a change stored from the detail can be
    /// written back into the caches holding this whiteboard, instead of them serving the
    /// pre-change list on the next read.
    var actionItems: [WBMacOSActionItem]
}
