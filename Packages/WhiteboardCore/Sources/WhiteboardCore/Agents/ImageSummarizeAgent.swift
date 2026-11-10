//
//  ImageSummarizeAgent.swift
//  WhiteboardCore
//
//  Created by Mark Su on 2026-08-04.
//

import Foundation
import RailtracksSwift

/// Provides a title, summary, and action items of a single captured image of meeting whiteboard.
///
/// Action items are read from the **image**, not derived from the generated summary: whiteboards
/// mark them visually (a boxed "TODO" corner, checkboxes, initials beside a line), and that signal
/// is lost once the board is flattened into a few sentences of prose. Extracting all three in one
/// vision call also keeps it to a single round-trip and a single failure mode.
struct ImageSummarizeAgent: RTSAgentNode {
    let id: UUID = UUID()
    let agentName: String
    let llmProvider: RTSLLMProvider
    let outputSchema: RTSOutputSchema?
    // Pure vision task — the model summarizes the supplied image directly; no search/tools needed.
    let tools: [any RTSToolNode] = []
    var inputs: RTSInput = [:]

    /// - Parameter modelIDString: Gemini model to run on. Required rather than defaulted: the model
    ///   is a user-facing setting now, and a default here would let a caller quietly run something
    ///   other than what Settings shows. `WBImageSummarizeService` is the one place that supplies
    ///   it, from `WBPreferences.analysisModelID`.
    init(modelIDString: String) {
        agentName = "image_summarize_agent"
        llmProvider = .gemini(modelIDString: modelIDString)
        outputSchema = Self.resultSchema
        inputs[inputKeySystemMessage] = .string(Self.systemMessage)
    }
}

private extension ImageSummarizeAgent {
    /// System prompt: read the captured whiteboard photo and produce a concise title, summary, and
    /// any action items written on the board.
    static let systemMessage = """
    You are given a single photo of a whiteboard captured during a meeting. Read everything legible \
    on the whiteboard — headings, diagrams, lists, and notes — and produce a concise title, a \
    summary of its content, and any action items it records.

    Produce:
    - `title`: a short, specific title naming what the whiteboard is about (a few words, no trailing \
    punctuation). Prefer the whiteboard's own heading if it has one.
    - `summary`: a clear, self-contained summary of the whiteboard's content in a few sentences — the \
    key points, decisions, or structure shown. Describe only what is actually visible; do not invent \
    details. If the image is unreadable or clearly not a whiteboard, say so briefly in the summary and \
    give a generic title.
    - `actionItems`: the tasks the whiteboard records — things someone is expected to go and do. \
    Include an item when the board marks it as one: a "TODO" / "Next steps" / "Action items" region, \
    a checkbox or empty box, an arrow or star pointing at a task, a line written as an instruction, or \
    a line tagged with an owner's name or initials or a due date. Write each as one short imperative \
    sentence, and keep any owner or date that is written on the board in the same sentence (for \
    example "Mark to send the revised quote by Friday").

    Rules for `actionItems`:
    - Return an empty array when the whiteboard records no tasks. Most whiteboards are diagrams, \
    notes, or discussion captures with no action items at all, and an empty array is the correct \
    answer for those. Never invent an item to avoid returning an empty array.
    - Include only what is written on the board. Do not infer tasks that a reader might reasonably \
    take away, and do not turn every bullet, heading, or label into an action item.
    - Do not repeat the summary as an action item, and do not list the same task twice.
    """

    /// Structured output: a title, a summary, and the action items of the whiteboard image.
    static let resultSchema = RTSOutputSchema(
        name: "ImageSummary",
        type: .object(
            name: "ImageSummary",
            properties: [
                RTSOutputSchema(
                    name: "title",
                    type: .string,
                    description: "A short, specific title for the whiteboard (a few words, no trailing punctuation)."
                ),
                RTSOutputSchema(
                    name: "summary",
                    type: .string,
                    description: "A clear, self-contained summary of the whiteboard's content in a few sentences, grounded only in what is visible in the image."
                ),
                RTSOutputSchema(
                    name: "actionItems",
                    type: .array(of: .string),
                    description: "The tasks written on the whiteboard, each as one short imperative sentence keeping any owner or due date written on the board. Empty when the whiteboard records no tasks — which is the common case."
                )
            ]
        )
    )
}
