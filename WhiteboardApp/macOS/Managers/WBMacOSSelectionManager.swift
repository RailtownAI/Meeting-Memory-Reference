import Observation

/// Shared state the column view models communicate through: the active sidebar destination
/// and what the user selected in the Home column. View models read and write this manager
/// instead of referencing each other.
@Observable
final class WBMacOSSelectionManager {
    /// Switching destination clears the selection — a whiteboard picked in one tab has no
    /// business staying open (in the detail inspector) over another.
    var sidebarItem = WBMacOSSidebarItem.home {
        didSet {
            if sidebarItem != oldValue {
                select(nil)
            }
        }
    }

    /// The whiteboard the detail column shows.
    private(set) var selectedWhiteboard: WBMacOSWhiteboard?

    /// Set when the user's last selection was a related meeting rather than a whiteboard —
    /// only one of the two is highlighted at a time.
    private(set) var selectedRelatedMeetingID: String?

    /// Set when the detail was opened from a schedule event (Today, This Week) — the event
    /// card stays highlighted while the detail (or its loading/empty state) shows.
    private(set) var selectedScheduleEventID: String?

    /// True while a flow resolves what the detail inspector should show — the inspector
    /// opens immediately in a loading state.
    private(set) var isDetailLoading = false

    /// True when the last detail load found nothing — the inspector stays open showing its
    /// empty state until dismissed or superseded.
    private(set) var isDetailEmpty = false

    /// Selects a whiteboard directly (thumbnail click, answer load), clearing any meeting
    /// selection and any in-flight or empty detail-load state.
    func select(_ whiteboard: WBMacOSWhiteboard?) {
        selectedWhiteboard = whiteboard
        selectedRelatedMeetingID = nil
        selectedScheduleEventID = nil
        isDetailLoading = false
        isDetailEmpty = false
    }

    /// Selects a related meeting. The whiteboard shown alongside stands in for a dedicated
    /// meeting-detail destination, which doesn't exist yet — it is deliberately **not**
    /// marked as the selected whiteboard; only the meeting highlights.
    func selectRelatedMeeting(_ meeting: WBMacOSRelatedMeeting, showing whiteboard: WBMacOSWhiteboard?) {
        selectedRelatedMeetingID = meeting.id
        isDetailLoading = false
        isDetailEmpty = false
        if let whiteboard {
            selectedWhiteboard = whiteboard
        }
    }

    /// Opens the detail inspector in a loading state while a flow resolves its content —
    /// pair with `endDetailLoad(showing:)`. A schedule event id keeps its card highlighted
    /// for the duration of the detail presentation.
    func beginDetailLoad(forScheduleEventID scheduleEventID: String? = nil) {
        selectedWhiteboard = nil
        selectedRelatedMeetingID = nil
        selectedScheduleEventID = scheduleEventID
        isDetailLoading = true
        isDetailEmpty = false
    }

    /// Replaces the selected whiteboard with a freshly-read copy of itself — same record, current
    /// content. Ignored if the selection moved on while the read was in flight.
    func replaceSelectedWhiteboard(with whiteboard: WBMacOSWhiteboard) {
        guard selectedWhiteboard?.id == whiteboard.id else {
            return
        }
        selectedWhiteboard = whiteboard
    }

    /// Replaces the selected whiteboard's action items after a change was stored, so the
    /// selection doesn't keep serving the pre-change list to whatever reads it next.
    func updateSelectedWhiteboardActionItems(
        _ items: [WBMacOSActionItem],
        forWhiteboardID whiteboardID: String
    ) {
        guard selectedWhiteboard?.id == whiteboardID else {
            return
        }
        selectedWhiteboard?.actionItems = items
    }

    /// Completes a detail load: shows the whiteboard, or the inspector's empty state when
    /// there is nothing to show. The originating schedule event (if any) stays highlighted.
    func endDetailLoad(showing whiteboard: WBMacOSWhiteboard?) {
        isDetailLoading = false
        if let whiteboard {
            selectedWhiteboard = whiteboard
            isDetailEmpty = false
        } else {
            isDetailEmpty = true
        }
    }
}
