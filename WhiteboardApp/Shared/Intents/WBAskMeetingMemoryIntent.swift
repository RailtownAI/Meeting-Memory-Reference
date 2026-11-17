//
//  WBAskMeetingMemoryIntent.swift
//  WhiteboardApp
//
//  Siri and Shortcuts: answers a question from the captured whiteboards, with the same prompt
//  search agent as the app's Search.
//

import AppIntents
import Foundation
import WhiteboardCore

struct WBAskMeetingMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Meeting Memory"
    static let description = IntentDescription(
        "Answers a question from your captured whiteboards, with their action items and meeting dates."
    )

    @Parameter(
        title: "Question",
        requestValueDialog: "What do you want to know about your meetings?"
    )
    var question: String

    @Dependency private var searchService: WBPromptSearchService
    @Dependency private var recordStore: WBWhiteboardRecordStore

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Meeting Memory \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        WBIntentReply.result(
            await Self.answer(question, searchService: searchService, recordStore: recordStore)
        )
    }

    /// The answer as one plain string: the agent's answer, then each supporting whiteboard with its
    /// date in full and its action items as sentences. Never throws; failures become a sentence
    /// that says what to do.
    ///
    /// Static, so the search intent and the tool twin share it, and so it can run without the
    /// system's intent runner.
    static func answer(
        _ question: String,
        searchService: WBPromptSearchService,
        recordStore: WBWhiteboardRecordStore
    ) async -> String {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return "Ask a question about your meetings, for example what was decided in the last design review."
        }
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let elapsed = clock.now - start
            WBLog.info("⏱️🗣️ Ask answered in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        }
        do {
            let (result, records) = try await withDeadline(seconds: WBIntentReply.waitSeconds) {
                let result = try await searchService.search(prompt: question)
                let records = try await recordStore.records(ids: Array(result.ids.prefix(3)))
                return (result, records)
            }
            let entities = await WBWhiteboardEntity.make(from: records)
            return text(answer: result.answer, whiteboards: entities)
        } catch is WBDeadlineExceeded {
            WBLog.warning("⚠️🗣️ Ask passed its \(WBIntentReply.waitSeconds)s deadline")
            return "Meeting Memory is taking longer than usual to search your whiteboards. Ask again in a moment, or use Search in the app."
        } catch {
            return WBIntentReply.message(for: error, action: "answer that")
        }
    }

    /// "<answer> From "Roadmap", captured Thursday, November 12, 2026, in Design review. Action
    /// items: Send the deck to Sam. Book the room."
    static func text(answer: String, whiteboards: [WBWhiteboardEntity]) -> String {
        var paragraphs = [WBIntentReply.plain(answer)]
        for whiteboard in whiteboards {
            var line = "From \"\(whiteboard.title)\", captured \(WBIntentReply.fullDate(whiteboard.capturedAt))"
            if let meeting = whiteboard.meetingTitle, !meeting.isEmpty {
                line += ", in \(meeting)"
            }
            line += "."
            if !whiteboard.actionItems.isEmpty {
                line += " Action items: " + whiteboard.actionItems.map(WBIntentReply.sentence).joined(separator: " ")
            }
            paragraphs.append(line)
        }
        return paragraphs.joined(separator: "\n\n")
    }
}
