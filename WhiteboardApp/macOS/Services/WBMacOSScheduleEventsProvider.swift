import EventKit
import Foundation
import WhiteboardCore

/// Provides the calendar events in a schedule window (a day, a week).
protocol WBMacOSScheduleEventsProviding {
    func events(from startDate: Date, to endDate: Date) async throws -> [WBMacOSScheduleEvent]
}

/// Real schedule-events provider: fetches the window's calendar events on-device via
/// EventKit and adapts them to the app-local model — personal details (title, location,
/// attendees) never travel through railengine.
///
/// The first fetch after install triggers the system calendar-access prompt (status
/// `.notDetermined`); once denied or restricted it returns an empty list, so the screen
/// degrades to its empty state. All-day events and events without a stable external
/// identifier are skipped — they can't link to captures.
struct WBMacOSEventKitScheduleEventsProvider: WBMacOSScheduleEventsProviding {
    private let service: WBEventKitService

    init(service: WBEventKitService = WBEventKitService()) {
        self.service = service
    }

    func events(from startDate: Date, to endDate: Date) async throws -> [WBMacOSScheduleEvent] {
        if service.authorizationStatus == .notDetermined {
            _ = try? await service.requestFullAccess()
        }
        guard service.hasFullAccess else {
            return []
        }
        let events = try await service.events(from: startDate, to: endDate)
        return events.compactMap { event in
            guard !event.isAllDay, let calendarEventID = event.externalIdentifier else {
                return nil
            }
            // Occurrences of a recurring event share EventKit's item identifier, so the
            // row id pairs it with the occurrence start — otherwise a week listing two
            // occurrences renders the first one twice (duplicate ForEach ids).
            return WBMacOSScheduleEvent(
                id: "\(event.id)@\(Int(event.startDate.timeIntervalSince1970))",
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                attendees: event.attendees.map {
                    WBMacOSAttendee(displayName: $0.displayName, email: $0.emailAddress)
                },
                calendarEventID: calendarEventID
            )
        }
    }
}
