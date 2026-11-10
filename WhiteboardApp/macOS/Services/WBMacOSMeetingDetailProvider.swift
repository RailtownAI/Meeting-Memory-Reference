import EventKit
import WhiteboardCore

/// Resolves the personal meeting data (title, attendees) that never travels through
/// railengine. Keyed by `WBMacOSWhiteboard.calendarEventID`, i.e. EventKit's
/// `calendarItemExternalIdentifier`, plus the occurrence start — recurring events share the
/// identifier across every instance, so the start pins which one to resolve (`nil` falls
/// back to the series master).
///
/// Returns `nil` when the identifier cannot be resolved — callers degrade gracefully.
protocol WBMacOSMeetingDetailProviding {
    func meetingDetail(
        forCalendarEventID calendarEventID: String,
        occurrenceStart: Date?
    ) async throws -> WBMacOSMeetingDetail?
}

/// Real meeting-detail provider: resolves the calendar event on-device via EventKit and maps
/// it to the app-local model — this type is the Core/app boundary for that path.
///
/// The first resolution after install triggers the system calendar-access prompt (status
/// `.notDetermined`); once denied or restricted it returns `nil` without prompting again, so
/// the screen can never break — the subtitle just degrades to the capture date.
struct WBMacOSEventKitMeetingDetailProvider: WBMacOSMeetingDetailProviding {
    private let service: WBEventKitService

    init(service: WBEventKitService = WBEventKitService()) {
        self.service = service
    }

    func meetingDetail(
        forCalendarEventID calendarEventID: String,
        occurrenceStart: Date?
    ) async throws -> WBMacOSMeetingDetail? {
        if service.authorizationStatus == .notDetermined {
            _ = try? await service.requestFullAccess()
        }
        guard service.hasFullAccess else {
            return nil
        }
        guard let event = try await resolvedEvent(
            forCalendarEventID: calendarEventID,
            occurrenceStart: occurrenceStart
        ) else {
            return nil
        }
        WBLog.debug(
            "Resolved event \(calendarEventID) '\(event.title)': organizer=\(event.organizer?.displayName ?? "none"), attendees=\(event.attendees.count)"
        )
        return WBMacOSMeetingDetail(
            calendarEventID: calendarEventID,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            attendees: WBEventAttendee.personList(
                organizer: event.organizer,
                attendees: event.attendees
            ).map { WBMacOSAttendee(displayName: $0.displayName, email: $0.emailAddress) }
        )
    }

    /// The event instance to resolve: with an `occurrenceStart`, the occurrence nearest to
    /// it within a ±1-day window (recurring events share the external identifier, and the
    /// bare identifier lookup only ever returns the series master); without one, that
    /// master lookup.
    private func resolvedEvent(
        forCalendarEventID calendarEventID: String,
        occurrenceStart: Date?
    ) async throws -> WBCalendarEvent? {
        if let occurrenceStart {
            let windowStart = occurrenceStart.addingTimeInterval(-86_400)
            let windowEnd = occurrenceStart.addingTimeInterval(86_400)
            let occurrences = try await service.events(from: windowStart, to: windowEnd)
                .filter { $0.externalIdentifier == calendarEventID }
            if let nearest = occurrences.min(by: {
                abs($0.startDate.timeIntervalSince(occurrenceStart))
                    < abs($1.startDate.timeIntervalSince(occurrenceStart))
            }) {
                return nearest
            }
        }
        return try await service.events(withExternalIdentifier: calendarEventID).first
    }
}
