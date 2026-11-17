//
//  WBiOSRememberWhiteboardIntent.swift
//  WhiteboardApp
//
//  Siri and Shortcuts: saves a whiteboard photo to a meeting, through the same pipeline as the
//  capture screens (summary and transcript, iCloud upload, railengine ingest). iOS only: the Mac
//  app never saves whiteboards.
//

import AppIntents
import Foundation
import UIKit
import UniformTypeIdentifiers
import WhiteboardCore

struct WBiOSRememberWhiteboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember Whiteboard"
    static let description = IntentDescription(
        "Saves a whiteboard photo to a meeting, with a title, summary and action items read from the photo."
    )

    @Parameter(
        title: "Photo",
        supportedContentTypes: [.image],
        requestValueDialog: "Which whiteboard photo?"
    )
    var photo: IntentFile

    @Parameter(
        title: "Meeting",
        description: "Leave empty for the meeting that started last, in progress or ended."
    )
    var meeting: WBiOSMeetingEntity?

    @Dependency private var meetingSync: WBiOSMeetingSyncService
    @Dependency private var eventService: WBEventKitService

    static var parameterSummary: some ParameterSummary {
        Summary("Remember \(\.$photo) in \(\.$meeting)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<WBWhiteboardEntity?> & ProvidesDialog {
        let outcome = await Self.remember(
            photo: photo,
            meeting: meeting,
            meetingSync: meetingSync,
            eventService: eventService,
            caller: "shortcut"
        )
        return .result(value: outcome.whiteboard, dialog: IntentDialog(stringLiteral: outcome.text))
    }

    /// What a Remember run produced: the saved whiteboard, or `nil` when it failed or is still
    /// saving, and a sentence saying which.
    struct Outcome: Sendable {
        let whiteboard: WBWhiteboardEntity?
        let text: String
    }

    /// Saves the photo to `meeting`; without one, to the meeting that started last
    /// (`WBiOSMeetingEntity.current`), in progress or ended. Never throws; failures become a
    /// sentence that says what to do.
    ///
    /// Static, so the tool twin shares it, and so it can run without the system's intent runner.
    /// `caller` names the intent that ran it, for the log.
    static func remember(
        photo: IntentFile,
        meeting: WBiOSMeetingEntity?,
        meetingSync: WBiOSMeetingSyncService,
        eventService: WBEventKitService,
        caller: String
    ) async -> Outcome {
        // First, before any early return: shows what Siri passed in, e.g. whether an onscreen
        // screenshot arrived as the photo.
        let photoText = "\(photo.filename) (\(photo.type?.identifier ?? "no type"))"
        let meetingText = meeting.map { "\"\($0.title)\" (\($0.id))" } ?? "none"
        WBLog.info("🗣️ Remember received from \(caller): photo \(photoText), meeting \(meetingText)")
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let elapsed = clock.now - start
            WBLog.info("⏱️🗣️ Remember finished in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        }

        guard eventService.hasFullAccess else {
            return Outcome(
                whiteboard: nil,
                text: "Meeting Memory needs full calendar access to link the whiteboard to a meeting. Open the app and allow it, then try again."
            )
        }
        // The vision calls are sent JPEG, as the capture screens send it; a shared photo can be
        // HEIC or PNG, and can arrive as a file reference rather than loaded data.
        let jpeg: Data
        switch await WBiOSIntentPhoto.jpeg(from: photo) {
        case .jpeg(let data):
            jpeg = data
        case .failed(let text):
            return Outcome(whiteboard: nil, text: text)
        }

        let target: WBiOSMeetingEntity
        if let meeting {
            target = meeting
        } else {
            do {
                let latest = try await WBiOSMeetingEntity.current(eventService: eventService)
                guard let current = latest else {
                    WBLog.info("🗣️ Remember found no meeting that started in the last day")
                    return Outcome(
                        whiteboard: nil,
                        text: "There is no meeting that started in the last day. Name the meeting to save the whiteboard to."
                    )
                }
                target = current
            } catch {
                return Outcome(
                    whiteboard: nil,
                    text: WBIntentReply.message(for: error, action: "find the meeting")
                )
            }
        }
        let targetText = "\"\(target.title)\" (\(target.id))"
        let source = meeting == nil ? "the meeting that started last" : "the meeting Siri passed"
        WBLog.info("🗣️ Remember saves to \(targetText), \(source)")

        let device = await MainActor.run { UIDevice.current.name }
        do {
            // Not cancelled at the deadline: by then the photo may be uploading, and the save should
            // finish if the app keeps running.
            // Indexed inside the operation, so a save that finishes after the deadline is indexed
            // too.
            let whiteboard = try await withDeadline(
                seconds: WBIntentReply.waitSeconds,
                cancelsOnTimeout: false
            ) {
                let record = try await save(
                    jpeg: jpeg,
                    to: target,
                    device: device,
                    meetingSync: meetingSync
                )
                let whiteboard = WBWhiteboardEntity(record: record, meetingTitle: target.title)
                await WBWhiteboardSpotlight.index([whiteboard])
                return whiteboard
            }
            return Outcome(whiteboard: whiteboard, text: text(saved: whiteboard, to: target))
        } catch is WBDeadlineExceeded {
            WBLog.warning("⚠️🗣️ Remember passed its \(WBIntentReply.waitSeconds)s deadline")
            return Outcome(
                whiteboard: nil,
                text: "Meeting Memory is still saving the whiteboard to \(target.title). It will be in that meeting's captures in the app when it is done."
            )
        } catch {
            return Outcome(
                whiteboard: nil,
                text: WBIntentReply.message(for: error, action: "save the whiteboard")
            )
        }
    }

    /// Links the meeting to its calendar record (ingesting one when railengine has none), then
    /// reads and saves the photo. Each step is timed in the log.
    private static func save(
        jpeg: Data,
        to meeting: WBiOSMeetingEntity,
        device: String,
        meetingSync: WBiOSMeetingSyncService
    ) async throws -> WBWhiteboardRecord {
        let clock = ContinuousClock()
        let start = clock.now
        let meetingID = try await meetingSync.resolveMeetingID(
            eventUID: meeting.eventUID,
            startEpoch: meeting.startEpoch
        )
        let elapsed = clock.now - start
        WBLog.info("⏱️📅 Meeting resolved in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        return try await WBWhiteboardCaptureService().captureAndSave(
            imageData: jpeg,
            meetingID: meetingID,
            eventUID: meeting.eventUID,
            occurrenceStart: meeting.start,
            capturedByDevice: device
        )
    }

    /// "Saved to Design review (Thursday, November 12, 2026): Roadmap. Action items: Send the deck
    /// to Sam. Book the room."
    static func text(
        saved whiteboard: WBWhiteboardEntity,
        to meeting: WBiOSMeetingEntity
    ) -> String {
        var text = "Saved to \(meeting.title) (\(WBIntentReply.fullDate(meeting.start))): \(WBIntentReply.sentence(whiteboard.title))"
        if !whiteboard.actionItems.isEmpty {
            text += " Action items: " + whiteboard.actionItems.map(WBIntentReply.sentence).joined(separator: " ")
        }
        return text
    }
}
