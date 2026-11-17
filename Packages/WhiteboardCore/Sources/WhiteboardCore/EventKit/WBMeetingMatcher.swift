//
//  WBMeetingMatcher.swift
//  WhiteboardCore
//

import Foundation

/// Finds calendar meetings by title: the matching shared by Remember Whiteboard's meeting picker
/// and the Siri meeting tool.
public enum WBMeetingMatcher {
    /// How far either side of today a title search looks.
    public static let titleSearchWindowDays = 7

    /// Whether an event can be a meeting someone names: all-day and canceled events are left out.
    public static func isCandidate(_ event: WBCalendarEvent) -> Bool {
        !event.isAllDay && event.status != .canceled
    }

    /// Whether `query` names an event titled `eventTitle`: the title contains the query, ignoring
    /// case. With `eitherWay`, the query may also contain the title ("prepare me for the weekly
    /// design review" names "Design Review"), and diacritics are ignored too.
    public static func title(
        _ eventTitle: String,
        matches query: String,
        eitherWay: Bool = false
    ) -> Bool {
        guard eitherWay else {
            return eventTitle.localizedCaseInsensitiveContains(query)
        }
        let eventTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventTitle.isEmpty, !query.isEmpty else {
            return false
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return eventTitle.range(of: query, options: options, locale: .current) != nil
            || query.range(of: eventTitle, options: options, locale: .current) != nil
    }
}

public extension WBEventKitService {
    /// Meetings whose title matches `query` (see `WBMeetingMatcher.title(_:matches:eitherWay:)`),
    /// from `days` before the start of `date`'s day to `days` after its end, sorted by start.
    /// Throws `accessDenied` without full calendar access.
    func meetings(
        titled query: String,
        around date: Date = Date(),
        withinDays days: Int = WBMeetingMatcher.titleSearchWindowDays,
        eitherWay: Bool = false
    ) throws -> [WBCalendarEvent] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard let from = calendar.date(byAdding: .day, value: -days, to: day),
              let to = calendar.date(byAdding: .day, value: days + 1, to: day)
        else {
            return []
        }
        return try events(from: from, to: to)
            .filter(WBMeetingMatcher.isCandidate)
            .filter { WBMeetingMatcher.title($0.title, matches: query, eitherWay: eitherWay) }
    }
}
