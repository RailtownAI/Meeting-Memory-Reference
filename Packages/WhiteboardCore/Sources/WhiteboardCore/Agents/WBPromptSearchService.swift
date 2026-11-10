//
//  WBPromptSearchService.swift
//  WhiteboardCore
//

import Foundation
import RailtownLogger
import RailtracksSwift

/// Errors thrown by `WBPromptSearchService`.
public enum WBPromptSearchError: Error, LocalizedError {
    /// No Gemini API key is stored in the Keychain — the user must add one in Settings.
    case missingGeminiAPIKey
    /// The agent finished but its output was not the expected `{answer, ids}` JSON.
    case invalidAgentOutput

    public var errorDescription: String? {
        switch self {
        case .missingGeminiAPIKey:
            return "Add your Gemini API key in Settings to search."
        case .invalidAgentOutput:
            return "The search agent returned an unexpected response. Try again."
        }
    }
}

/// The prompt-search agent's structured result: a short grounded answer plus the ids of the
/// whiteboard records that support it, most-relevant first.
public struct WBPromptSearchResult: Codable, Hashable, Sendable {
    public let answer: String
    public let ids: [String]
}

/// Public entry point for answering a question from the whiteboard knowledge base.
///
/// Runs `PromptSearchAgent` as the root of an `RTSFlow` — a single agent with `PhotoSearchTool`,
/// no orchestrator. The agent searches the whiteboard vector store, grounds its answer in the
/// results, and emits `{answer, ids}`. Resolving the ids to full records is the caller's next
/// step (`WBWhiteboardRecordStore`).
public struct WBPromptSearchService: Sendable {

    public init() {}

    /// Answers `prompt` from the captured whiteboard knowledge base.
    public func search(prompt: String) async throws -> WBPromptSearchResult {
        guard let geminiAPIKey = WBKeychainStore.readGeminiAPIKey() else {
            throw WBPromptSearchError.missingGeminiAPIKey
        }
        let gateway = RTSLLMGateway(apiKeys: [.gemini: geminiAPIKey])
        let flow = RTSFlow(title: "Prompt Search")
        // Ship this run's trace to Conductr once it's written. Subscribed before `run` so nothing is
        // missed; the `defer` clears the subscription if the run ends without writing a trace, so an
        // abandoned search doesn't leave one waiting forever. See `WBImageSummarizeService`.
        let traceSubscription = ConductrTraceUploader.shared.subscribe(to: flow.outputFileURLPublisher)
        defer {
            ConductrTraceUploader.shared.cancelSubscription(traceSubscription)
        }
        do {
            let rawResult = try await flow.run(
                agent: PromptSearchAgent(),
                prompt: prompt,
                gateway: gateway
            )
            let result = try JSONDecoder().decode(
                WBPromptSearchResult.self,
                from: Data(rawResult.utf8)
            )
            return result
        } catch {
            WBLog.error("Prompt search failed: \(error)")
            throw error
        }
    }
}
