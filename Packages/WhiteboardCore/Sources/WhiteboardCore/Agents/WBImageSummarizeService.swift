//
//  WBImageSummarizeService.swift
//  WhiteboardCore
//

import Foundation
import RailtownLogger
import RailtracksSwift

/// Errors thrown by `WBImageSummarizeService`.
public enum WBImageSummarizeError: Error, LocalizedError {
    /// No Gemini API key is stored in the Keychain — the user must add one in Settings.
    case missingGeminiAPIKey
    /// The agent finished but its output was not the expected `{title, summary}` JSON.
    case invalidAgentOutput

    public var errorDescription: String? {
        switch self {
        case .missingGeminiAPIKey:
            return "Add your Gemini API key in Settings to summarize whiteboards."
        case .invalidAgentOutput:
            return "The summarizer returned an unexpected response. Try again."
        }
    }
}

/// The image-summarize agent's structured result: a title, a summary, and the action items read off
/// a captured whiteboard.
public struct WBImageSummary: Codable, Hashable, Sendable {
    public let title: String
    public let summary: String

    /// Tasks written on the whiteboard, one short sentence each. Empty for the common case of a
    /// whiteboard that records no tasks at all.
    public let actionItems: [String]

    public init(title: String, summary: String, actionItems: [String] = []) {
        self.title = title
        self.summary = summary
        self.actionItems = actionItems
    }

    /// Decoded by hand so a missing `actionItems` key falls back to empty rather than failing the
    /// whole decode. The output schema marks the field required, but a title and summary are still
    /// worth showing if a model ever omits it — losing the review screen over an absent array would
    /// be a poor trade.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
    }
}

/// Public entry point for generating a title, summary, and action items from a captured whiteboard
/// image.
///
/// Runs `ImageSummarizeAgent` as the root of an `RTSFlow` with the image attached as multimodal
/// input; the vision model returns `{title, summary, actionItems}`. The caller supplies
/// provider-friendly image bytes (normalize platform images to JPEG on the app side, as the SDK's
/// vision path expects).
public struct WBImageSummarizeService: Sendable {

    public init() {}

    /// Generates a title and summary for the whiteboard in `imageData`.
    public func summarize(
        imageData: Data,
        mimeType: String = "image/jpeg"
    ) async throws -> WBImageSummary {
        guard let geminiAPIKey = WBKeychainStore.readGeminiAPIKey() else {
            throw WBImageSummarizeError.missingGeminiAPIKey
        }
        // Read per call, like the key above: the caller holds this service for the life of a screen,
        // so anything resolved in `init` would keep running the model that was set when the screen
        // opened.
        let modelIDString = WBPreferences.analysisModelID
        let gateway = RTSLLMGateway(apiKeys: [.gemini: geminiAPIKey])
        let flow = RTSFlow(title: "Image Summarize")
        // Ship this run's trace to Conductr once it's written. Subscribed before `run` so nothing is
        // missed. The trace is sent before `run` returns, so by the time this scope exits the
        // subscription has either fired and released itself, or the run ended without one — the
        // user cancelling mid-capture — and the `defer` clears it rather than leaving it waiting
        // forever for a value that will never come.
        let traceSubscription = ConductrTraceUploader.shared.subscribe(to: flow.outputFileURLPublisher)
        defer {
            ConductrTraceUploader.shared.cancelSubscription(traceSubscription)
        }
        let image = RTSImage(data: imageData, mimeType: mimeType)
        do {
            WBLog.debug("🤖 Calling LLM for image summary with model: \(modelIDString)")
            let rawResult = try await flow.run(
                agent: ImageSummarizeAgent(modelIDString: modelIDString),
                prompt: "Generate a concise title and a summary for this whiteboard.",
                gateway: gateway,
                images: [image]
            )
            WBLog.debug("🤖 Received LLM summary result")
            return try JSONDecoder().decode(
                WBImageSummary.self,
                from: Data(rawResult.utf8)
            )
        } catch let error as DecodingError {
            WBLog.error("Image summarize returned unexpected output: \(error)")
            throw WBImageSummarizeError.invalidAgentOutput
        } catch {
            WBLog.error("Image summarize failed: \(error)")
            throw error
        }
    }
}
