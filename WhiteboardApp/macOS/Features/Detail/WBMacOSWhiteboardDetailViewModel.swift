import Foundation
import Observation

/// View model for the detail column: reads the shown whiteboard from the shared selection
/// manager, pages across its meeting's captures, resolves the meeting's personal details
/// through the meeting-detail manager, and carries the image provider the view needs to
/// build the image views.
@Observable
final class WBMacOSWhiteboardDetailViewModel {

    /// Nested — does not repeat the `WBMacOS` prefix, per the coding style.
    enum Segment: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case ocrText = "OCR Text"
        case details = "Details"

        var id: String {
            rawValue
        }
    }

    private let manager: WBMacOSSelectionManager
    private let sessionManager: WBMacOSAnswerSessionManager
    private let meetingDetailManager: WBMacOSMeetingDetailManager

    let imageProvider: WBMacOSWhiteboardImageProviding
    let attendeeImageProvider: WBMacOSAttendeeImageProviding
    let actionItemsProvider: WBMacOSActionItemsProviding

    var selectedSegment = Segment.summary

    /// Whiteboard page currently visible in the carousel — the sections below follow it.
    var visibleWhiteboardID: String?

    /// Whether the "+x" attendees popover is shown.
    var isAttendeesPopoverShown = false

    init(
        imageProvider: WBMacOSWhiteboardImageProviding,
        attendeeImageProvider: WBMacOSAttendeeImageProviding,
        actionItemsProvider: WBMacOSActionItemsProviding,
        manager: WBMacOSSelectionManager,
        sessionManager: WBMacOSAnswerSessionManager,
        meetingDetailManager: WBMacOSMeetingDetailManager
    ) {
        self.imageProvider = imageProvider
        self.attendeeImageProvider = attendeeImageProvider
        self.actionItemsProvider = actionItemsProvider
        self.manager = manager
        self.sessionManager = sessionManager
        self.meetingDetailManager = meetingDetailManager
    }

    var whiteboard: WBMacOSWhiteboard? {
        manager.selectedWhiteboard
    }

    /// True while a flow (e.g. opening a Today event) is still resolving what to show.
    var isDetailLoading: Bool {
        manager.isDetailLoading
    }

    /// True when that resolution found nothing — the view shows its empty state.
    var isDetailEmpty: Bool {
        manager.isDetailEmpty
    }

    /// Every capture of the shown whiteboard's meeting — one record per photo, matching the
    /// railengine contract, so the carousel pages whiteboards rather than images.
    ///
    /// Prefers the meeting's full fetched capture set; until that loads, falls back to the
    /// answer's siblings (the agent cites at most a handful of records, so the answer set
    /// may miss captures the fetch returns).
    var meetingWhiteboards: [WBMacOSWhiteboard] {
        guard let whiteboard else {
            return []
        }
        guard let meetingID = whiteboard.meetingID else {
            return [whiteboard]
        }
        if let fetchedWhiteboards = meetingDetailManager.whiteboards(forMeetingID: meetingID) {
            return fetchedWhiteboards
        }
        let siblings = (sessionManager.answerState.value?.whiteboards ?? [])
            .filter { $0.meetingID == meetingID }
        return siblings.isEmpty ? [whiteboard] : siblings
    }

    /// The whiteboard whose content the sections show — follows the visible carousel page.
    var displayedWhiteboard: WBMacOSWhiteboard? {
        meetingWhiteboards.first { $0.id == visibleWhiteboardID } ?? whiteboard
    }

    /// `mailto:` draft for the shown whiteboard — every attendee email as recipient, the
    /// whiteboard's title as subject, and its summary as body. Follows the visible carousel
    /// page. `nil` (button disabled) while no whiteboard shows or the meeting's attendees
    /// haven't resolved yet — a draft should never open without its recipients.
    var emailURL: URL? {
        guard let whiteboard = displayedWhiteboard else {
            return nil
        }
        let recipients = (meetingDetail?.attendees ?? []).compactMap(\.email)
        guard !recipients.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipients.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "subject", value: whiteboard.title),
            URLQueryItem(name: "body", value: whiteboard.summary),
        ]
        return components.url
    }

    /// Adopts a stored action-items change into the shared state, so the caches the detail
    /// rebuilds from don't serve the pre-change list back to the section.
    func actionItemsDidChange(_ items: [WBMacOSActionItem], forWhiteboardID whiteboardID: String) {
        meetingDetailManager.updateActionItems(items, forWhiteboardID: whiteboardID)
        manager.updateSelectedWhiteboardActionItems(items, forWhiteboardID: whiteboardID)
    }

    var meetingDetail: WBMacOSMeetingDetail? {
        meetingDetailManager.detail(
            forCalendarEventID: whiteboard?.calendarEventID,
            occurrenceStart: whiteboard?.occurrenceStart
        )
    }

    /// Called by the view whenever the shown whiteboard changes (`.task(id:)`): resets the
    /// segment, carousel, and popover, and resolves the meeting detail. A failed or
    /// unresolvable lookup simply leaves the detail absent — the subtitle then degrades to
    /// just the capture date.
    func whiteboardDidChange() async {
        selectedSegment = .summary
        visibleWhiteboardID = whiteboard?.id
        isAttendeesPopoverShown = false
        await refreshShownWhiteboard()
        await meetingDetailManager.loadDetail(
            forCalendarEventID: whiteboard?.calendarEventID,
            occurrenceStart: whiteboard?.occurrenceStart
        )
        await meetingDetailManager.loadWhiteboards(forMeetingID: whiteboard?.meetingID)
    }

    /// Re-reads the opened whiteboard from storage, so the detail shows the record as it stands
    /// rather than as whoever selected it had it.
    ///
    /// A search result carries the record as the vector store answered with it, and a cached
    /// capture set was fetched once — either can be behind an edit made since (here or on another
    /// device). A failed read leaves what's on screen alone.
    private func refreshShownWhiteboard() async {
        guard let whiteboardID = whiteboard?.id else {
            return
        }
        guard let refreshed = await meetingDetailManager.refreshWhiteboard(id: whiteboardID) else {
            return
        }
        manager.replaceSelectedWhiteboard(with: refreshed)
    }
}
