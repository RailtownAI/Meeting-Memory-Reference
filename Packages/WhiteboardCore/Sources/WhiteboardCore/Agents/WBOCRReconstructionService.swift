//
//  WBOCRReconstructionService.swift
//  WhiteboardCore
//

import Foundation
import RailtownLogger
import RailtracksSwift

/// Errors thrown by `WBOCRReconstructionService`.
public enum WBOCRReconstructionError: Error, LocalizedError {
    /// No Gemini API key is stored in the Keychain — the user must add one in Settings.
    case missingGeminiAPIKey
    /// The agent finished but its output was not the expected `{text}` JSON.
    case invalidAgentOutput

    public var errorDescription: String? {
        switch self {
        case .missingGeminiAPIKey:
            return "Add your Gemini API key in Settings to read whiteboards."
        case .invalidAgentOutput:
            return "The transcriber returned an unexpected response. Try again."
        }
    }
}

/// Rebuilds a readable transcript from Vision's scattered fragments by handing them, with their
/// positions and the photo they came from, to `OCRReconstructAgent`.
///
/// The `appleOCRThenAgent` half of `WBOCRMode`; `WBImageTranscribeService` is the other.
public struct WBOCRReconstructionService: Sendable {

    public init() {}

    /// Reconstructs the transcript for `segments`, reading their arrangement off `imageData`.
    /// Returns `""` when handed nothing.
    public func reconstruct(
        segments: [WBOCRSegment],
        imageData: Data,
        mimeType: String = "image/jpeg"
    ) async throws -> String {
        guard !segments.isEmpty else {
            return ""
        }
        guard let geminiAPIKey = WBKeychainStore.readGeminiAPIKey() else {
            throw WBOCRReconstructionError.missingGeminiAPIKey
        }
        // Read per call, like the key above, so a model changed in Settings applies to the next
        // run without a relaunch — the caller holds this service for the life of a screen.
        let modelIDString = WBPreferences.analysisModelID
        let gateway = RTSLLMGateway(apiKeys: [.gemini: geminiAPIKey])
        let flow = RTSFlow(title: "OCR Reconstruct")
        // Ship this run's trace to Conductr once it's written — same lifecycle as the summarize
        // flow: subscribed before `run` so nothing is missed, released either way on the way out.
        let traceSubscription = ConductrTraceUploader.shared.subscribe(to: flow.outputFileURLPublisher)
        defer {
            ConductrTraceUploader.shared.cancelSubscription(traceSubscription)
        }
        do {
            WBLog.debug("🤖 Calling LLM to reconstruct \(segments.count) OCR fragment(s)")
            let rawResult = try await flow.run(
                agent: OCRReconstructAgent(modelIDString: modelIDString),
                prompt: Self.prompt(for: segments),
                gateway: gateway,
                images: [RTSImage(data: imageData, mimeType: mimeType)]
            )
            let transcript = try JSONDecoder().decode(
                WBWhiteboardTranscript.self,
                from: Data(rawResult.utf8)
            )
            WBLog.debug("🤖 Reconstructed transcript of \(transcript.text.count) character(s)")
            return transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as DecodingError {
            WBLog.error("OCR reconstruction returned unexpected output: \(error)")
            throw WBOCRReconstructionError.invalidAgentOutput
        } catch {
            WBLog.error("OCR reconstruction failed: \(error)")
            throw error
        }
    }
}

private extension WBOCRReconstructionService {

    /// The fragments as one per line, with top-left coordinates rounded to three decimals — enough
    /// to place them on the board, short enough not to bloat the prompt.
    ///
    /// Listed top-to-bottom so the model starts from something close to reading order; it is free
    /// to disagree, and has the coordinates and the image to do so.
    static func prompt(for segments: [WBOCRSegment]) -> String {
        let lines = segments
            .sorted { $0.topLeftBoundingBox.minY < $1.topLeftBoundingBox.minY }
            .map { segment -> String in
                let box = segment.topLeftBoundingBox
                let position = "x=\(rounded(box.minX)) y=\(rounded(box.minY)) w=\(rounded(box.width)) h=\(rounded(box.height))"
                return "\(position) \"\(segment.text)\""
            }
            .joined(separator: "\n")

        return """
        Reconstruct the whiteboard transcript from these \(segments.count) fragments:

        \(lines)
        """
    }

    static func rounded(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }
}
