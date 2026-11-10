import Foundation

/// A meeting related to the current answer, as the Home column lists it.
///
/// App-local model: built from railengine results, with the personal title and start time
/// re-resolved on-device via EventKit where possible — the wire `title` is the whiteboard
/// content title, kept only as the fallback for unresolvable events.
struct WBMacOSRelatedMeeting: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date

    /// EventKit `calendarItemExternalIdentifier` (`eventUID` on the wire), used for the
    /// on-device resolution. `nil` when the record didn't carry one.
    let calendarEventID: String?
}
