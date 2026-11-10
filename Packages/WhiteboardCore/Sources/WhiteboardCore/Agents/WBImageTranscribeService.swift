//
//  WBImageTranscribeService.swift
//  WhiteboardCore
//

import Foundation
import RailtownLogger
import RailtracksSwift

/// Errors thrown by `WBImageTranscribeService`.
public enum WBImageTranscribeError: Error, LocalizedError {
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

/// The transcribe agent's structured result.
struct WBWhiteboardTranscript: Codable, Hashable, Sendable {
    let text: String
}

/// Public entry point for transcribing the writing on a captured whiteboard.
///
/// Runs `ImageTranscribeAgent` as the root of an `RTSFlow` with the image attached, mirroring
/// `WBImageSummarizeService`. The caller supplies provider-friendly image bytes (normalize platform
/// images to JPEG on the app side, as the SDK's vision path expects).
public struct WBImageTranscribeService: Sendable {

    public init() {}

    /// Transcribes the whiteboard in `imageData`. Returns `""` for a board with no legible writing,
    /// which is a result rather than a failure.
    public func transcribe(
        imageData: Data,
        mimeType: String = "image/jpeg"
    ) async throws -> String {
        guard let geminiAPIKey = WBKeychainStore.readGeminiAPIKey() else {
            throw WBImageTranscribeError.missingGeminiAPIKey
        }
        // Read per call, like the key above, so a model changed in Settings applies to the next
        // run without a relaunch — the caller holds this service for the life of a screen.
        let modelIDString = WBPreferences.analysisModelID
        let gateway = RTSLLMGateway(apiKeys: [.gemini: geminiAPIKey])
        let flow = RTSFlow(title: "Image Transcribe")
        // Ship this run's trace to Conductr once it's written — same lifecycle as the summarize
        // flow: subscribed before `run` so nothing is missed, released either way on the way out.
        let traceSubscription = ConductrTraceUploader.shared.subscribe(to: flow.outputFileURLPublisher)
        defer {
            ConductrTraceUploader.shared.cancelSubscription(traceSubscription)
        }
        let image = RTSImage(data: imageData, mimeType: mimeType)
        do {
            WBLog.debug("🤖 Calling LLM to transcribe whiteboard")
            let rawResult = try await flow.run(
                agent: ImageTranscribeAgent(modelIDString: modelIDString),
                prompt: "Transcribe everything written on this whiteboard.",
                gateway: gateway,
                images: [image]
            )
            let transcript = try JSONDecoder().decode(
                WBWhiteboardTranscript.self,
                from: Data(rawResult.utf8)
            )
            WBLog.debug("🤖 Transcribed \(transcript.text.count) character(s)")
            return transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as DecodingError {
            WBLog.error("Whiteboard transcription returned unexpected output: \(error)")
            throw WBImageTranscribeError.invalidAgentOutput
        } catch {
            WBLog.error("Whiteboard transcription failed: \(error)")
            throw error
        }
    }
}
