//
//  WBAskMeetingMemoryToolIntent.swift
//  WhiteboardApp
//
//  Ask Meeting Memory as a tool Siri's model can call (27.3). Shares `WBAskMeetingMemoryIntent.answer`;
//  in its own file so it can be dropped without touching the 27.0 intents.
//

import AppIntents
import WhiteboardCore

@available(iOS 27.3, macOS 27.3, *)
@AppIntent(.tool)
struct WBAskMeetingMemoryToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Meeting Memory"
    static let description = IntentDescription(
        "Answers a question from the user's captured meeting whiteboards. Returns the answer as plain text, with each supporting whiteboard's capture date in full, its meeting, and its action items as sentences."
    )

    @Parameter(
        title: "Question",
        description: "The question about the user's meetings or whiteboards."
    )
    var question: String

    @Dependency private var searchService: WBPromptSearchService
    @Dependency private var recordStore: WBWhiteboardRecordStore

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        WBIntentReply.result(
            await WBAskMeetingMemoryIntent.answer(
                question,
                searchService: searchService,
                recordStore: recordStore
            )
        )
    }
}
