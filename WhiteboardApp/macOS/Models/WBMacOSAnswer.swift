import Foundation

/// One question, the agent's answer to it, and the whiteboards and meetings the answer
/// references.
struct WBMacOSAnswer: Hashable {
    let question: String
    let text: String
    let whiteboards: [WBMacOSWhiteboard]
    let relatedMeetings: [WBMacOSRelatedMeeting]
}
