//
//  ImageTranscribeAgent.swift
//  WhiteboardCore
//

import Foundation
import RailtracksSwift

/// Transcribes everything written on a captured whiteboard, laid out the way the board lays it out.
///
/// Reads the photo directly rather than re-ordering fragments from an on-device OCR pass. A
/// whiteboard's meaning is carried as much by its arrows, boxes, and grouping as by its words, and
/// those are drawn — an OCR engine never returns them, so anything working from fragments alone is
/// guessing at how they relate. Reading the image also handles handwriting better than Vision does,
/// and doesn't inherit its clipped or garbled fragments.
///
/// Separate from `ImageSummarizeAgent` on purpose: that one describes the board in a few sentences,
/// this one reproduces it. Prose can't be searched for a phrase somebody actually wrote.
struct ImageTranscribeAgent: RTSAgentNode {
    let id: UUID = UUID()
    let agentName: String
    let llmProvider: RTSLLMProvider
    let outputSchema: RTSOutputSchema?
    // Pure vision task — the model reads the supplied image directly; no search/tools needed.
    let tools: [any RTSToolNode] = []
    var inputs: RTSInput = [:]

    /// - Parameter modelIDString: Gemini model to run on. Required rather than defaulted, matching
    ///   `ImageSummarizeAgent`: the model is a user-facing setting, and a default here would let a
    ///   caller quietly run something other than what Settings shows. `WBImageTranscribeService` is the
    ///   one place that supplies it, from `WBPreferences.analysisModelID`.
    init(modelIDString: String) {
        agentName = "image_transcribe_agent"
        llmProvider = .gemini(modelIDString: modelIDString)
        outputSchema = Self.resultSchema
        inputs[inputKeySystemMessage] = .string(Self.systemMessage)
    }
}

private extension ImageTranscribeAgent {
    static let systemMessage = """
    You are given a photo of a whiteboard captured during a meeting. Write out everything written on \
    it, as plain text, laid out the way the board lays it out. This is a transcript: reproduce the \
    board, do not describe or summarize it.

    Most whiteboards are one of two things, and they want different treatment:

    **Diagrams** (boxes, arrows, flows — a flow chart, an architecture sketch)
    - One box per line, using the box's own label. Two boxes side by side are two lines, never one — \
    do not run them together into a sentence just because they sit at the same height.
    - Write an arrow as `A -> B` on its own line, using the labels of the boxes it joins. A label \
    written on the arrow goes with it: `A -> B (label)`.
    - Where one box fans out to several, write each connection on its own line.
    - Group each branch together and separate branches with a blank line, so the shape of the \
    diagram survives in the text.

    **Written notes** (headings, lists, sentences)
    - Keep the board's lines as lines, in reading order.
    - Read a column all the way down before moving to the next; never sweep across the board and \
    interleave two columns into the same lines.
    - Keep a heading on its own line above what it heads, and list items on their own lines. \
    Separate distinct regions with a blank line.

    Rules:
    - Transcribe what is written, not what it means. Never summarize, never explain, never translate, \
    and never add a word that isn't on the board.
    - Keep the board's own wording and spelling, including its abbreviations and any misspelling — \
    someone searching for what they wrote should find it as they wrote it.
    - Where handwriting is genuinely illegible, write `[illegible]` rather than guessing.
    - Ignore anything that isn't board content: a person, a hand, a reflection, the wall around it.
    - Return an empty string when the photo has no legible writing at all — a blank board, or a \
    photo that isn't of a whiteboard.
    """

    /// Structured output: the board's writing as plain text.
    static let resultSchema = RTSOutputSchema(
        name: "WhiteboardTranscript",
        type: .object(
            name: "WhiteboardTranscript",
            properties: [
                RTSOutputSchema(
                    name: "text",
                    type: .string,
                    description: "Everything written on the whiteboard, as plain text in reading order, laid out the way the board lays it out. Empty when the board holds no legible writing."
                )
            ]
        )
    )
}
