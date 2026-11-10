//
//  OCRReconstructAgent.swift
//  WhiteboardCore
//

import Foundation
import RailtracksSwift

/// Puts the fragments an on-device OCR pass recognized back into the order they were written in.
///
/// The counterpart to `ImageTranscribeAgent`, and the other half of the comparison behind
/// `WBOCRMode`: there the model reads the board itself, here it only arranges what Vision read.
/// Anchoring the wording to Vision means the transcript can't drift from an on-device read — at the
/// cost of inheriting Vision's mistakes, which on handwriting are plenty.
///
/// The photo is attached as well as the fragments. Arrows and boxes are drawn, so OCR never returns
/// them, and without the image the model would be guessing at how the fragments relate — which is
/// the whole job.
struct OCRReconstructAgent: RTSAgentNode {
    let id: UUID = UUID()
    let agentName: String
    let llmProvider: RTSLLMProvider
    let outputSchema: RTSOutputSchema?
    // Pure reasoning over the supplied fragments and image — no search or tools needed.
    let tools: [any RTSToolNode] = []
    var inputs: RTSInput = [:]

    /// - Parameter modelIDString: Gemini model to run on. Required rather than defaulted, matching
    ///   `ImageSummarizeAgent`: the model is a user-facing setting, and a default here would let a
    ///   caller quietly run something other than what Settings shows. `WBOCRReconstructionService` is the
    ///   one place that supplies it, from `WBPreferences.analysisModelID`.
    init(modelIDString: String) {
        agentName = "ocr_reconstruct_agent"
        llmProvider = .gemini(modelIDString: modelIDString)
        outputSchema = Self.resultSchema
        inputs[inputKeySystemMessage] = .string(Self.systemMessage)
    }
}

private extension OCRReconstructAgent {
    static let systemMessage = """
    You are given a photo of a whiteboard and the text fragments an OCR engine recognized on it, \
    each with the box it occupies. Write out what the board says, laid out the way the board lays \
    it out.

    Take the **wording** from the fragments — that is what OCR actually read — and use the **image** \
    to see how they relate: which fragments sit inside the same box, what an arrow joins to what, \
    and which parts of the board are separate. Arrows and boxes are drawn, so they are never among \
    the fragments; the image is the only place you can see them.

    Coordinates are normalized to the range 0 to 1, with the origin at the **top left**: `x` grows \
    to the right, `y` grows downward, and `w`/`h` are the fragment's width and height.

    Produce `text`: the board's content as plain text.

    Most whiteboards are one of two things, and they want different treatment:

    **Diagrams** (boxes, arrows, flows — a flow chart, an architecture sketch)
    - One box per line. Two boxes side by side are two lines, never one — do not run them together \
    into a sentence just because they share a `y`. Fragments inside the *same* box belong on one \
    line together.
    - Write an arrow as `A -> B` on its own line, using the box labels it joins. Read the arrows off \
    the image. A label written on an arrow goes with it: `A -> B (label)`.
    - Where one box fans out to several, write each connection on its own line.
    - Group each branch of the diagram together and separate branches with a blank line, so the \
    shape of the diagram survives.

    **Written notes** (headings, lists, sentences)
    - Put fragments that form one line of writing on one line, in left-to-right order. Handwriting \
    slants, so a line can drift downward as it goes — judge it by the run of fragments, not an exact \
    `y`.
    - Read a column all the way down before moving to the next; never sweep across the board and \
    interleave two columns into the same lines.
    - Keep a heading on its own line above what it heads, and list items on their own lines. \
    Separate distinct regions with a blank line.

    Rules:
    - Take the wording from the fragments. Never translate, never rewrite, and never summarize or \
    describe the board — this is a transcript, not a caption.
    - Every fragment must appear, and only once. The exception is a fragment that is really a piece \
    of drawing OCR mistook for text — a stray `>`, `→`, `|`, `-`, or a box edge. Never emit those as \
    words: use them as the connector they are, or leave them out.
    - A fragment OCR garbled is still the fragment: copy it as given. The one thing you may fix is a \
    character clipped at a fragment's edge when the image makes the intended word unambiguous — for \
    example a title read as "gentHub" where the board plainly reads "AgentHub".
    - Return an empty string only if no fragments were supplied.
    """

    /// Structured output: the reconstructed transcript.
    static let resultSchema = RTSOutputSchema(
        name: "OCRTranscript",
        type: .object(
            name: "OCRTranscript",
            properties: [
                RTSOutputSchema(
                    name: "text",
                    type: .string,
                    description: "The whiteboard's writing as plain text, in reading order, containing every supplied fragment exactly once and nothing else."
                )
            ]
        )
    )
}
