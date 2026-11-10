import Foundation

/// How a captured whiteboard's text is read.
///
/// Both routes end at the same place — one transcript in `WBWhiteboardRecord.ocrText` — but they
/// divide the work differently, and which reads a real board better is an open question. Switched
/// in code (`WBOCRService.mode`) rather than exposed in Settings: it's here to compare the two
/// while the answer is unsettled, not for the user to choose.
public enum WBOCRMode: Sendable {
    /// Apple's on-device Vision recognizes the text; the model is given those fragments with their
    /// positions and the photo, and puts them in reading order. The wording is Vision's, so it
    /// can't drift from what was recognized — but Vision struggles with handwriting.
    case appleOCRThenAgent

    /// The model reads the photo itself. It handles handwriting better and sees the arrows and
    /// grouping, at the cost of the transcript no longer being anchored to an on-device read.
    case agentOnly

    var title: String {
        switch self {
        case .appleOCRThenAgent: return "Apple OCR + agent"
        case .agentOnly: return "Agent only"
        }
    }
}
