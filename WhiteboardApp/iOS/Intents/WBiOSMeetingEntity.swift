//
//  WBiOSMeetingEntity.swift
//  WhiteboardApp
//
//  A calendar meeting a whiteboard can be saved to, for Remember Whiteboard.
//

import AppIntents
import Foundation
import WhiteboardCore

/// One occurrence of a calendar event, read from EventKit on this device.
///
/// `id` is the `WBMeetingID` (`<eventUID>#<startEpoch>`): the external identifier alone is shared
/// by every occurrence of a recurring meeting, so the start pins the one meant.
struct WBiOSMeetingEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Meeting",
        numericFormat: "\(placeholder: .int) meetings"
    )

    static let defaultQuery = WBiOSMeetingEntityQuery()

    let id: String

    /// `calendarItemExternalIdentifier`, stable across devices.
    let eventUID: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Start")
    var start: Date

    @Property(title: "End")
    var end: Date

    var displayRepresentation: DisplayRepresentation {
        let day = start.formatted(date: .abbreviated, time: .omitted)
        let startTime = start.formatted(date: .omitted, time: .shortened)
        let endTime = end.formatted(date: .omitted, time: .shortened)
        let times = "\(startTime) – \(endTime)"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(day), \(times)",
            image: .init(systemName: "calendar")
        )
    }

    var startEpoch: Int {
        Int(start.timeIntervalSince1970)
    }

    /// `nil` for an event without an external identifier, which can't be linked to a record.
    init?(event: WBCalendarEvent) {
        guard let eventUID = event.externalIdentifier else {
            return nil
        }
        self.eventUID = eventUID
        id = WBMeetingID.mint(
            eventUID: eventUID,
            startEpoch: Int(event.startDate.timeIntervalSince1970)
        )
        title = event.title
        start = event.startDate
        end = event.endDate
    }

    /// The meeting a capture goes to when none is named: the one whose start is latest among the
    /// meetings that started in the last day (24 hours), whether it is still in progress or has
    /// ended. Uses Home's filter (all-day, canceled and declined events, and birthday and
    /// subscription calendars left out) but not its 15-minute look-ahead, so a meeting that hasn't
    /// started yet is never picked. A meeting that started more than a day ago is not picked even
    /// when it is still in progress.
    static func current(
        eventService: WBEventKitService,
        now: Date = Date()
    ) async throws -> WBiOSMeetingEntity? {
        // Every candidate started at or before `now`.
        let candidates = try await eventService.recentStartedMeetings(withinDays: 1, now: now)
        // Latest start; on a tie, the latest end. Of meetings with the same start, one in progress
        // ends after any that has ended, so this prefers the one in progress, then the longest.
        let latest = candidates.max {
            ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate)
        }
        // A latest event that can't be an entity gives nil rather than an older meeting, so the
        // photo is never saved to the wrong one.
        guard let latest else {
            return nil
        }
        return WBiOSMeetingEntity(event: latest)
    }
}

/// Finds meetings: by id, by title within a week either side of today, and yesterday's and today's
/// as suggestions. Lookups throw `accessDenied` without full calendar access; suggestions are then
/// empty.
struct WBiOSMeetingEntityQuery: EntityStringQuery {
    /// How many days of meetings, today included, are suggested: yesterday and today.
    static let suggestionDays = 2

    /// The most meetings suggested; the oldest are dropped past it.
    static let suggestionLimit = 50

    /// One calendar service for every lookup, the one the app registers at launch.
    @Dependency private var eventService: WBEventKitService

    func entities(for identifiers: [String]) async throws -> [WBiOSMeetingEntity] {
        var meetings: [WBiOSMeetingEntity] = []
        for identifier in identifiers {
            // `<eventUID>#<startEpoch>`; the UID itself may contain "#", so split at the last one.
            guard let separator = identifier.lastIndex(of: "#"),
                  let startEpoch = Int(identifier[identifier.index(after: separator)...])
            else {
                continue
            }
            let eventUID = String(identifier[..<separator])
            let start = Date(timeIntervalSince1970: TimeInterval(startEpoch))
            // A window around the start rather than a lookup by external identifier, which can
            // answer with a recurring event's first occurrence instead of this one.
            let events = try await eventService.events(
                from: start.addingTimeInterval(-60),
                to: start.addingTimeInterval(60)
            )
            if let event = events.first(where: {
                $0.externalIdentifier == eventUID && Int($0.startDate.timeIntervalSince1970) == startEpoch
            }), let meeting = WBiOSMeetingEntity(event: event) {
                meetings.append(meeting)
            }
        }
        return meetings
    }

    func entities(matching string: String) async throws -> [WBiOSMeetingEntity] {
        try await eventService
            .meetings(titled: string)
            .compactMap(WBiOSMeetingEntity.init(event:))
    }

    /// Meetings from the start of yesterday to the end of today, newest start first and at most
    /// `suggestionLimit`. These are also the meeting names Siri learns for the Remember Whiteboard
    /// phrases, so yesterday's meeting can be named too. Empty without full calendar access, so a
    /// parameter update never fails.
    func suggestedEntities() async throws -> [WBiOSMeetingEntity] {
        guard eventService.hasFullAccess else {
            WBLog.info("🗣️ Suggested meetings: none, no full calendar access")
            return []
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysBack = -(Self.suggestionDays - 1)
        guard let from = calendar.date(byAdding: .day, value: daysBack, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        else {
            return []
        }
        let meetings = try await eventService.events(from: from, to: tomorrow)
            .filter(WBMeetingMatcher.isCandidate)
            // An event that began before `from` but runs into it is fetched too; leave it out.
            .filter { $0.startDate >= from }
            .compactMap(WBiOSMeetingEntity.init(event:))
        let suggestions = Array(meetings.reversed().prefix(Self.suggestionLimit))
        let count = suggestions.count
        WBLog.info("🗣️ Suggested meetings: \(count)")
        return suggestions
    }
}
