import Foundation

/// Personal calendar data for a meeting — re-fetched on-device from EventKit via
/// `calendarEventID`, never stored in `WBCoreModel` or sent to railengine. Titles and attendees
/// are the meeting's most identifying details, so they stay on the device that already has them
/// through the user's calendar account; only the event identifier and scheduled times travel.
struct WBMacOSMeetingDetail: Identifiable, Hashable {
    let calendarEventID: String
    let title: String
    let startDate: Date
    let endDate: Date

    let attendees: [WBMacOSAttendee]

    var id: String {
        calendarEventID
    }
}
