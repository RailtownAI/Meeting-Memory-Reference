import Foundation

/// The date window a schedule tab lists — Today and This Week share the schedule view and
/// view model, differing only in this scope.
enum WBMacOSScheduleScope {
    case today
    case thisWeek

    var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This Week"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .today: return "No meetings today"
        case .thisWeek: return "No meetings this week"
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .today: return "Events on today's calendar show up here."
        case .thisWeek: return "Events on this week's calendar show up here."
        }
    }

    /// Whether event rows spell out the weekday — redundant within a single day, needed to
    /// tell days apart across a week.
    var showsWeekday: Bool {
        self == .thisWeek
    }

    /// The half-open window to fetch: the day containing `now`, or the calendar week
    /// containing it (per the user's calendar settings, e.g. Monday-based weeks).
    func dateInterval(now: Date = .now) -> DateInterval? {
        let calendar = Calendar.current
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        }
    }
}
