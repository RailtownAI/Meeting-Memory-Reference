//
//  PromptSearchAgent.swift
//  WhiteboardCore
//
//  Created by Mark Su on 2026-07-30.
//

import Foundation
import RailtracksSwift

/// Answers a prompt/question about captured meeting whiteboards.
///
/// Uses `PhotoSearchTool` to search the whiteboard vector store, grounds its answer only in the
/// returned results, and outputs a short answer plus the `id`s of the results that support it.
struct PromptSearchAgent: RTSAgentNode {
    let id: UUID = UUID()
    let agentName: String
    let llmProvider: RTSLLMProvider
    let outputSchema: RTSOutputSchema?
    let tools: [any RTSToolNode] = [PhotoSearchTool()]
    var inputs: RTSInput = [:]

    init() {
        agentName = "prompt_search_agent"
        llmProvider = .gemini(modelIDString: RTSGeminiModelID.gemini3Flash.modelIDString)
        outputSchema = Self.resultSchema
        inputs[inputKeySystemMessage] = .string(Self.systemMessage)
    }
}

private extension PromptSearchAgent {
    /// System prompt defining the agent's role, its use of the search tool, and its output contract.
    static let systemMessage = """
    You are a retrieval assistant for a meeting-whiteboard knowledge base. Each entry is a photo of a \
    whiteboard captured during a meeting, stored with a title, summary, OCR text, keywords, and \
    action items.

    To answer the user's question you MUST use the "Photo_Summary_Search" tool to find the most \
    relevant whiteboard entries. Derive a concise search query from the user's question and call the \
    tool; you may call it again with a refined query if the first results are weak.

    Ground your answer ONLY in the content returned by the tool — do not invent facts that the \
    results don't support. If the results don't contain the answer, say so plainly.

    Each tool result includes an `id` field alongside its content. Produce:
    - `answer`: a short, direct answer to the question (a few sentences at most).
    - `ids`: include **only** results that genuinely support your answer — you decide how many based \
    on relevance, not a fixed count. Do **not** pad to reach a number, and omit tangential or weakly \
    related results. Return **at most 5**, ordered most-relevant first; as few as 1, or an empty \
    array if none are relevant (in which case say nothing relevant was found). Use only `id`s \
    returned by the tool.
    """

    /// Structured output: a short answer plus the ids of the supporting search results.
    static let resultSchema = RTSOutputSchema(
        name: "PromptSearchResult",
        type: .object(
            name: "PromptSearchResult",
            properties: [
                RTSOutputSchema(
                    name: "answer",
                    type: .string,
                    description: "A short, direct answer to the user's question, grounded only in the search results."
                ),
                RTSOutputSchema(
                    name: "ids",
                    type: .array(of: .string),
                    description: "The `id` values of the results that genuinely support the answer, most-relevant first — the model decides how many by relevance (no padding). At most 5; as few as 1; empty if none are relevant."
                )
            ]
        )
    )
}
