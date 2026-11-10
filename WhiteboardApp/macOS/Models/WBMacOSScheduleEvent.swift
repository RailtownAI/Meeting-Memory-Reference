import Foundation

/// A calendar event on a schedule tab (Today, This Week), as the schedule screen lists it.
///
/// App-local model: the real implementation maps these from EventKit's events for the
/// window — personal details (title, location, attendees) never travel through railengine.
struct WBMacOSScheduleEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let attendees: [WBMacOSAttendee]

    /// EventKit `calendarItemExternalIdentifier`, linking the event to its captures.
    let calendarEventID: String
}
