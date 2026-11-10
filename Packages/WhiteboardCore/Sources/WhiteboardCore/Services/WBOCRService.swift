//
//  WBOCRService.swift
//  WhiteboardCore
//

import Foundation
import Vision

/// Extracts the text written on a captured whiteboard, on-device via Vision.
///
/// Vision returns one observation per detected text segment, in no guaranteed reading order. This
/// service pre-joins them into the **single string** both the review UI and the ingestion contract
/// (`WBWhiteboardRecord.ocrText`) expect — callers never see the segments.
///
/// The transcript comes from `ImageTranscribeAgent` reading the photo, with on-device Vision as the
/// fallback. A whiteboard's meaning is carried as much by its arrows, boxes, and grouping as by its
/// words, and those are drawn — an OCR engine returns scattered fragments with no way to tell which
/// belong together, so any ordering built from them alone is guesswork. The model also reads
/// handwriting better, which is what whiteboards are made of.
///
/// Vision still runs when the model can't: no API key, no network, a malformed response. Its
/// fragments are ordered geometrically (see `joinSegments`), which is worse but never nothing.
///
/// A photo with no legible text is **not** an error: transcription simply yields `""`.
public struct WBOCRService: Sendable {

    /// Which route reads the text. Flip this to compare the two on the same board — there is no
    /// user-facing setting, deliberately: it is a comparison switch while the better route is an
    /// open question, and one of the two goes away once that settles.
    static let mode: WBOCRMode = .agentOnly

    private let transcription = WBImageTranscribeService()
    private let reconstruction = WBOCRReconstructionService()

    public init() {}

    /// Reads the text off the whiteboard in `imageData` and returns it as one transcript, by
    /// whichever route `mode` selects. Returns `""` when the photo holds no legible text.
    public func recognizeText(
        imageData: Data,
        languages: [Locale.Language] = [Locale.Language(identifier: "en-US")]
    ) async throws -> String {
        WBLog.debug("👁️ Reading whiteboard text — mode: \(Self.mode.title)")
        do {
            switch Self.mode {
            case .agentOnly:
                let transcript = try await transcription.transcribe(imageData: imageData)
                WBLog.debug("👁️ Transcribed \(transcript.count) character(s) from the image")
                // An empty transcript is a real answer here — a blank board — so it is returned
                // as-is rather than sending Vision after a second opinion.
                return transcript

            case .appleOCRThenAgent:
                let segments = try await recognizeSegments(imageData: imageData, languages: languages)
                guard !segments.isEmpty else {
                    return ""
                }
                let reconstructed = try await reconstruction.reconstruct(
                    segments: segments,
                    imageData: imageData
                )
                guard !reconstructed.isEmpty else {
                    WBLog.warning("⚠️👁️ Reconstruction returned nothing — falling back to geometric order")
                    return Self.joinSegments(segments)
                }
                WBLog.debug("👁️ Reconstructed \(reconstructed.count) character(s) from \(segments.count) fragment(s)")
                return reconstructed
            }
        } catch {
            WBLog.warning("⚠️👁️ \(Self.mode.title) failed (\(error)) — falling back to on-device OCR")
        }
        let segments = try await recognizeSegments(imageData: imageData, languages: languages)
        return Self.joinSegments(segments)
    }

    /// The raw fragments Vision recognized, each with its position. Exposed for callers that want
    /// to arrange the text themselves; `recognizeText(imageData:languages:)` is the usual entry.
    public func recognizeSegments(
        imageData: Data,
        languages: [Locale.Language] = [Locale.Language(identifier: "en-US")]
    ) async throws -> [WBOCRSegment] {
        var request = RecognizeTextRequest()
        // Whiteboards are mostly handwriting — `.accurate` handles it far better than `.fast`, and
        // language correction recovers characters the strokes leave ambiguous.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        WBLog.debug("👁️ Starting OCR on captured image")
        let observations = try await request.perform(on: imageData)
        let segments = observations.compactMap { observation -> WBOCRSegment? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return WBOCRSegment(text: text, boundingBox: observation.boundingBox.cgRect)
        }
        WBLog.debug("👁️ OCR found \(segments.count) fragment(s)")
        return segments
    }
}

private extension WBOCRService {

    /// The share of the shorter segment's height that two segments must overlap vertically to
    /// count as the same line. Low enough to hold a slanted line together, high enough that
    /// stacked lines — which barely graze each other — stay apart.
    static let sameLineOverlapRatio: CGFloat = 0.3

    /// Joins the segments into a single transcript in reading order: one line per line of writing,
    /// its words in left-to-right order, lines top to bottom.
    ///
    /// The fallback for when `WBOCRReconstructionService` can't run. A hand-held photo is always
    /// slightly skewed, so "same line" is decided by **vertical overlap with the segment already
    /// placed** rather than by distance from a fixed anchor: comparing against a line's first
    /// segment breaks a line that descends as it goes, because each word sits a little lower than
    /// the last until the drift passes the tolerance and cuts the line in two. Comparing neighbours
    /// lets a line slant as far as it likes while stacked lines, which don't overlap at all, still
    /// separate.
    ///
    /// What it can't do is read layout — two columns at the same height merge into one line here,
    /// which is the reason the model does this when it can.
    static func joinSegments(_ segments: [WBOCRSegment]) -> String {
        // Top of the photo first — descending, because Vision's y grows upward.
        let topToBottom = segments.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var lines: [[WBOCRSegment]] = []
        for segment in topToBottom {
            if let previous = lines.last?.last, sharesLine(previous, segment) {
                lines[lines.count - 1].append(segment)
            } else {
                lines.append([segment])
            }
        }

        return lines
            .map { line in
                line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .map(\.text)
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    /// Whether two segments belong to the same line of writing, by how much their vertical spans
    /// overlap relative to the shorter one — so a big heading beside small text isn't dragged in
    /// just because the heading is tall enough to reach it.
    static func sharesLine(_ first: WBOCRSegment, _ second: WBOCRSegment) -> Bool {
        let firstBox = first.boundingBox
        let secondBox = second.boundingBox
        let overlap = min(firstBox.maxY, secondBox.maxY) - max(firstBox.minY, secondBox.minY)
        guard overlap > 0 else {
            return false
        }
        let shorterHeight = min(firstBox.height, secondBox.height)
        guard shorterHeight > 0 else {
            return false
        }
        return overlap / shorterHeight >= sameLineOverlapRatio
    }
}
