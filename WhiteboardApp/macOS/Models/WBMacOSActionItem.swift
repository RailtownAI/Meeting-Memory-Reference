import Foundation

/// One action item captured from a whiteboard — every whiteboard carries its own list.
///
/// Mirrors Core's `WBActionItem` (the wire contract), whose `status` is the string this
/// models as `isDone`: a capture ingests every item as "unknown" (a board records the task,
/// not whether it's done), and checking one off here is the user saying otherwise.
struct WBMacOSActionItem: Identifiable, Hashable {
    let id: String
    var text: String
    var isDone: Bool
}
