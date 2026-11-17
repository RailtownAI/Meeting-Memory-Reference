//
//  WBSearchWhiteboardsIntent.swift
//  WhiteboardApp
//
//  The system in-app search schema: a way for Siri to reach the app without an App Shortcut
//  phrase. Siri passes the search term; the intent answers it the same way as Ask Meeting Memory
//  and returns the answer, so it does not depend on what the app shows when it opens.
//

import AppIntents
import WhiteboardCore

@available(iOS 27, macOS 27, *)
@AppIntent(schema: .system.searchInApp)
struct WBSearchWhiteboardsIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency private var searchService: WBPromptSearchService
    @Dependency private var recordStore: WBWhiteboardRecordStore

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        WBLog.info("🗣️ Siri in-app search received")
        return WBIntentReply.result(
            await WBAskMeetingMemoryIntent.answer(
                criteria.term,
                searchService: searchService,
                recordStore: recordStore
            )
        )
    }
}
