import Foundation

/// Shared date formatting for the macOS UI. Members carry the `wbMacOS` prefix so they
/// cannot collide with other `Date` extensions.
extension Date {
    /// "Today, 11:23 AM", "Yesterday, 3:04 PM", or "Jul 24, 9:00 AM".
    var wbMacOSCapturedAtText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today, " + formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) {
            return "Yesterday, " + formatted(date: .omitted, time: .shortened)
        }
        return formatted(date: .abbreviated, time: .shortened)
    }

    /// Captured-at text with the meeting title appended when known,
    /// e.g. "Today, 11:23 AM · Apple Demo".
    func wbMacOSSubtitle(meetingTitle: String?) -> String {
        guard let meetingTitle, !meetingTitle.isEmpty else {
            return wbMacOSCapturedAtText
        }
        return wbMacOSCapturedAtText + " · " + meetingTitle
    }
}
