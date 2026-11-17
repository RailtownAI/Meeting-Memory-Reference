//
//  WBWhiteboardCaptureService.swift
//  WhiteboardCore
//

import Foundation

/// The whole capture pipeline without a screen: read the photo (summary ∥ transcript), then save
/// it to a meeting (iCloud upload + railengine ingest).
///
/// The capture screens run the same steps one at a time, because each step drives its own spinner
/// and retry — `WBImageSummarizeService` and `WBOCRService` on review, `WBWhiteboardSaveService` on
/// the result screen. This composes those services for callers with no UI in between, such as the
/// Remember Whiteboard App Intent, and keeps their rules: a failed summary fails the capture, a
/// failed transcript only leaves `ocrText` empty.
///
/// Each step logs how long it took, so a run from Siri can be timed against its deadline.
public struct WBWhiteboardCaptureService: Sendable {

    /// What reading the photo produced.
    private struct Analysis: Sendable {
        let summary: WBImageSummary
        /// The transcript, or `""` when the photo holds no legible text or transcription failed.
        let ocrText: String
    }

    private let summarizer = WBImageSummarizeService()
    private let ocrService = WBOCRService()
    private let saveService = WBWhiteboardSaveService()

    public init() {}

    /// Summarizes and transcribes the JPEG in `imageData`, concurrently. Throws only when the
    /// summary fails: a transcript failure is logged and gives an empty `ocrText`, as on the
    /// review screen.
    private func analyze(imageData: Data) async throws -> Analysis {
        let clock = ContinuousClock()
        let start = clock.now
        async let summary = summarizer.summarize(imageData: imageData)
        async let transcript = transcribe(imageData: imageData)
        let result = Analysis(summary: try await summary, ocrText: await transcript)
        let elapsed = clock.now - start
        WBLog.info("⏱️🖼️ Analysis took \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        return result
    }

    /// Reads the photo and saves it to the meeting. Returns the record as ingested.
    ///
    /// `imageData` must be JPEG, which is what the vision calls are sent as.
    public func captureAndSave(
        imageData: Data,
        meetingID: String,
        eventUID: String,
        occurrenceStart: Date,
        capturedByDevice: String
    ) async throws -> WBWhiteboardRecord {
        let clock = ContinuousClock()
        let analysis = try await analyze(imageData: imageData)
        let saveStart = clock.now
        let ids = WBWhiteboardSaveService.makeIDs()
        let record = try await saveService.save(
            imageData: imageData,
            id: ids.id,
            imageID: ids.imageID,
            title: analysis.summary.title,
            summary: analysis.summary.summary,
            ocrText: analysis.ocrText,
            actionItems: WBActionItem.make(from: analysis.summary.actionItems),
            meetingID: meetingID,
            eventUID: eventUID,
            occurrenceStart: occurrenceStart,
            capturedByDevice: capturedByDevice
        )
        let elapsed = clock.now - saveStart
        WBLog.info("⏱️💾 Upload and ingest took \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        return record
    }

    private func transcribe(imageData: Data) async -> String {
        do {
            return try await ocrService.recognizeText(imageData: imageData)
        } catch {
            let description = "\(error)"
            WBLog.error("⚠️👁️ OCR failed: \(description)")
            return ""
        }
    }
}
