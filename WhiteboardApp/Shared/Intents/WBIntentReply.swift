//
//  WBIntentReply.swift
//  WhiteboardApp
//
//  What the Siri and Shortcuts actions answer with, and how errors read out loud.
//

import AppIntents
import Foundation
import SwiftUI
import WhiteboardCore

nonisolated enum WBIntentReply {
    /// How long an action waits for its run. The system gives an iOS background action about 30
    /// seconds; this leaves room to answer before that.
    static let waitSeconds: Double = 25

    /// The text as the action's value, as the spoken dialog, and on screen.
    ///
    /// The value carries the whole answer as plain text: with Siri's AI the dialog and snippet may
    /// not be shown, and Siri passes the value on (an action item to Reminders, a date to
    /// Calendar).
    static func result(
        _ text: String
    ) -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        .result(
            value: text,
            dialog: IntentDialog(stringLiteral: text),
            view: WBIntentReplyView(text: text)
        )
    }

    /// "Thursday, November 12, 2026": dates said in full, so they survive being passed on.
    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// `text` as a sentence: trimmed, ending in a full stop unless it already ends a sentence.
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return trimmed
        }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    /// Markdown as plain sentences: no heading or list markers, no emphasis, links as their text.
    static func plain(_ markdown: String) -> String {
        let lines = markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacing(#/^(#+|[-*•]|\d+\.)\s+/#, with: "")
            }
            .joined(separator: "\n")
        let inline = try? AttributedString(
            markdown: lines,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return inline.map { String($0.characters) } ?? lines
    }

    /// A sentence for `error` that says what to do, never a raw error dump. The error itself goes
    /// to the log.
    static func message(for error: any Error, action: String) -> String {
        let description = "\(error)"
        WBLog.error("⚠️🗣️ \(action) failed: \(description)")
        switch error {
        case WBPromptSearchError.missingGeminiAPIKey, WBImageSummarizeError.missingGeminiAPIKey:
            return "Meeting Memory needs a Gemini API key. Add it in the app's Settings, then try again."
        case WBWhiteboardRecordStoreError.missingEnginePAT, WBWhiteboardIngestionStoreError.missingEngineToken:
            return "Meeting Memory needs its whiteboard engine keys. Add them in the app's Settings, then try again."
        case WBCalendarRecordStoreError.missingEnginePAT, WBCalendarIngestionStoreError.missingEngineToken:
            return "Meeting Memory needs its calendar engine keys. Add them in the app's Settings, then try again."
        case WBEventKitService.WBEventKitError.accessDenied:
            return "Meeting Memory needs full calendar access. Allow it in the Settings app, then try again."
        case is WBFileStore.WBFileStoreError:
            return "Meeting Memory could not save the photo to iCloud Drive. Check that iCloud Drive is on, then try again."
        case _ where [401, 403].contains(WBHTTPStatus.code(of: error)):
            return "Meeting Memory's engine keys were rejected. Update them in the app's Settings, then try again."
        case let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost || urlError.code == .timedOut:
            return "Meeting Memory could not reach the network. Check the connection, then try again."
        default:
            return "Meeting Memory could not \(action) right now. Try again in a moment."
        }
    }
}

/// The answer under Siri's dialog and in Shortcuts.
struct WBIntentReplyView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }
}
