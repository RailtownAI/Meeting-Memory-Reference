import Observation

/// View model for the root split view: reads the active sidebar destination the content
/// column switches on, and carries the managers and providers the column views need to
/// build their own view models.
@Observable
final class WBMacOSRootViewModel {

    let manager: WBMacOSSelectionManager
    let sessionManager: WBMacOSAnswerSessionManager
    let meetingDetailManager: WBMacOSMeetingDetailManager
    let imageProvider: WBMacOSWhiteboardImageProviding
    let attendeeImageProvider: WBMacOSAttendeeImageProviding
    let actionItemsProvider: WBMacOSActionItemsProviding
    let scheduleEventsProvider: WBMacOSScheduleEventsProviding
    let eventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding

    init(
        manager: WBMacOSSelectionManager,
        sessionManager: WBMacOSAnswerSessionManager,
        meetingDetailManager: WBMacOSMeetingDetailManager,
        imageProvider: WBMacOSWhiteboardImageProviding,
        attendeeImageProvider: WBMacOSAttendeeImageProviding,
        actionItemsProvider: WBMacOSActionItemsProviding,
        scheduleEventsProvider: WBMacOSScheduleEventsProviding,
        eventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding
    ) {
        self.manager = manager
        self.sessionManager = sessionManager
        self.meetingDetailManager = meetingDetailManager
        self.imageProvider = imageProvider
        self.attendeeImageProvider = attendeeImageProvider
        self.actionItemsProvider = actionItemsProvider
        self.scheduleEventsProvider = scheduleEventsProvider
        self.eventWhiteboardsProvider = eventWhiteboardsProvider
    }

    var destination: WBMacOSSidebarItem {
        manager.sidebarItem
    }

    /// Whether the detail inspector is shown — presented whenever a whiteboard is selected
    /// (directly, or as the destination of a related-meeting click), while a detail load is
    /// in flight, or when a load came back empty; hidden until then. Dismissing the
    /// inspector clears all of that state so the two can never disagree.
    var isDetailPresented: Bool {
        get {
            manager.selectedWhiteboard != nil
                || manager.isDetailLoading
                || manager.isDetailEmpty
        }
        set {
            if !newValue {
                manager.select(nil)
            }
        }
    }
}
