import Observation

/// View model for the Home column: projects the shared answer session and selection state,
/// and forwards user actions to the managers. Fetching lives in the session manager so the
/// request and its state survive this view model being recreated with its view.
@Observable
final class WBMacOSHomeViewModel {

    private let manager: WBMacOSSelectionManager
    private let sessionManager: WBMacOSAnswerSessionManager

    let imageProvider: WBMacOSWhiteboardImageProviding

    init(
        imageProvider: WBMacOSWhiteboardImageProviding,
        manager: WBMacOSSelectionManager,
        sessionManager: WBMacOSAnswerSessionManager
    ) {
        self.imageProvider = imageProvider
        self.manager = manager
        self.sessionManager = sessionManager
    }

    var searchText: String {
        get {
            sessionManager.searchText
        }
        set {
            sessionManager.searchText = newValue
        }
    }

    var answerState: WBMacOSLoadState<WBMacOSAnswer> {
        sessionManager.answerState
    }

    var whiteboards: [WBMacOSWhiteboard] {
        answerState.value?.whiteboards ?? []
    }

    var relatedMeetings: [WBMacOSRelatedMeeting] {
        answerState.value?.relatedMeetings ?? []
    }

    /// The whiteboard to ring in the thumbnail strip — none while a meeting is selected.
    var selectedWhiteboardID: WBMacOSWhiteboard.ID? {
        guard manager.selectedRelatedMeetingID == nil else {
            return nil
        }
        return manager.selectedWhiteboard?.id
    }

    var selectedRelatedMeetingID: String? {
        manager.selectedRelatedMeetingID
    }

    func submitSearch() {
        sessionManager.submit(question: searchText)
    }

    /// Selects the whiteboard — or clears the selection when it is already the ringed one,
    /// so clicking again toggles the detail closed.
    func selectWhiteboard(_ whiteboard: WBMacOSWhiteboard) {
        if selectedWhiteboardID == whiteboard.id {
            manager.select(nil)
        } else {
            manager.select(whiteboard)
        }
    }

    /// Opens the meeting's details — or clears the selection when the meeting is already
    /// selected, so clicking again toggles it off. Only the meeting is marked selected;
    /// showing its first captured whiteboard in the detail inspector is the stand-in until
    /// a real meeting-detail destination exists.
    func selectRelatedMeeting(_ meeting: WBMacOSRelatedMeeting) {
        if manager.selectedRelatedMeetingID == meeting.id {
            manager.select(nil)
            return
        }
        let whiteboard = whiteboards.first { $0.meetingID == meeting.id }
        manager.selectRelatedMeeting(meeting, showing: whiteboard)
    }
}
