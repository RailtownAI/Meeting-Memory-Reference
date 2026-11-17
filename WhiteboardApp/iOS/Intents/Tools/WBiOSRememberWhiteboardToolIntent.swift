//
//  WBiOSRememberWhiteboardToolIntent.swift
//  WhiteboardApp
//
//  Remember Whiteboard as a tool Siri's model can call (27.3). Shares
//  `WBiOSRememberWhiteboardIntent.remember`; in its own file so it can be dropped without touching the
//  27.0 intents.
//

import AppIntents
import UniformTypeIdentifiers
import WhiteboardCore

@available(iOS 27.3, *)
@AppIntent(.tool)
struct WBiOSRememberWhiteboardToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember Whiteboard"
    static let description = IntentDescription(
        "Saves a photo of a whiteboard to a calendar meeting and reads its title, summary and action items. Without a meeting, uses the meeting that started last, whether it is still in progress or has ended."
    )

    @Parameter(
        title: "Photo",
        description: "A photo of the whiteboard.",
        supportedContentTypes: [.image]
    )
    var photo: IntentFile

    @Parameter(title: "Meeting", description: "The meeting the whiteboard belongs to.")
    var meeting: WBiOSMeetingEntity?

    @Dependency private var meetingSync: WBiOSMeetingSyncService
    @Dependency private var eventService: WBEventKitService

    func perform() async throws -> some IntentResult & ReturnsValue<WBWhiteboardEntity?> & ProvidesDialog {
        let outcome = await WBiOSRememberWhiteboardIntent.remember(
            photo: photo,
            meeting: meeting,
            meetingSync: meetingSync,
            eventService: eventService,
            caller: "tool"
        )
        return .result(value: outcome.whiteboard, dialog: IntentDialog(stringLiteral: outcome.text))
    }
}
