import Foundation
import Observation
import WhiteboardCore

/// View model for a schedule column (Today, This Week): loads the scope's calendar events
/// and opens an event's meeting details. The only object that talks to the schedule-events
/// and event-whiteboards providers.
@Observable
final class WBMacOSScheduleViewModel {

    private let scheduleEventsProvider: WBMacOSScheduleEventsProviding
    private let eventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding
    private let manager: WBMacOSSelectionManager

    let scope: WBMacOSScheduleScope
    let attendeeImageProvider: WBMacOSAttendeeImageProviding

    private(set) var eventsState = WBMacOSLoadState<[WBMacOSScheduleEvent]>.idle

    init(
        scope: WBMacOSScheduleScope,
        scheduleEventsProvider: WBMacOSScheduleEventsProviding,
        eventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding,
        attendeeImageProvider: WBMacOSAttendeeImageProviding,
        manager: WBMacOSSelectionManager
    ) {
        self.scope = scope
        self.scheduleEventsProvider = scheduleEventsProvider
        self.eventWhiteboardsProvider = eventWhiteboardsProvider
        self.attendeeImageProvider = attendeeImageProvider
        self.manager = manager
    }

    func load() async {
        eventsState = .loading
        guard let window = scope.dateInterval() else {
            eventsState = .loaded([])
            return
        }
        do {
            let events = try await scheduleEventsProvider.events(from: window.start, to: window.end)
            guard !Task.isCancelled else {
                return
            }
            eventsState = .loaded(events)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            eventsState = .failed(error.localizedDescription)
        }
    }

    /// The event whose detail is currently presented — drives the card highlight.
    var selectedEventID: String? {
        manager.selectedScheduleEventID
    }

    /// Opens the event's meeting details — or clears the selection when the event is already
    /// the open one, so tapping again toggles the inspector closed (its only dismissal on
    /// this tab). Otherwise the inspector opens immediately in a loading state while the
    /// event's captures are fetched, then shows the first one — or its empty state when the
    /// event has no captures (or the fetch fails, which is also logged).
    func openEvent(_ event: WBMacOSScheduleEvent) {
        if manager.selectedScheduleEventID == event.id {
            manager.select(nil)
            return
        }
        manager.beginDetailLoad(forScheduleEventID: event.id)
        Task {
            do {
                let whiteboards = try await eventWhiteboardsProvider.whiteboards(
                    forCalendarEventID: event.calendarEventID,
                    occurrenceStart: event.startDate
                )
                guard !Task.isCancelled else {
                    return
                }
                if whiteboards.isEmpty {
                    WBLog.info("No captures found for event \(event.calendarEventID)")
                }
                manager.endDetailLoad(showing: whiteboards.first)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                WBLog.error(
                    "Event whiteboards fetch failed for \(event.calendarEventID): \(error)"
                )
                manager.endDetailLoad(showing: nil)
            }
        }
    }
}
