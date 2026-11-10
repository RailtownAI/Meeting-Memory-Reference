import Foundation

/// An action item extracted from a whiteboard capture.
///
/// Matches the backend contract. `status` and `assigneeRef` are kept as raw wire values
/// (`assigneeRef` is an opaque person reference, or `nil` when unassigned).
public struct WBActionItem: Codable, Sendable {
    /// Stable action-item id (e.g. "ai_01").
    public let id: String

    /// The action item text.
    public var text: String

    /// Status string (e.g. "open").
    public var status: String

    /// Opaque reference to the assigned person, or `nil` if unassigned.
    public var assigneeRef: String?

    public init(id: String, text: String, status: String, assigneeRef: String? = nil) {
        self.id = id
        self.text = text
        self.status = status
        self.assigneeRef = assigneeRef
    }
}

public extension WBActionItem {
    /// Status for an item read off a whiteboard: the board records the task, not whether it's done.
    static let statusUnknown = "unknown"

    /// Builds records from the plain strings an extractor produced — currently the vision model's
    /// `actionItems`. Blank entries are dropped.
    ///
    /// Ids are fresh `UUID`s rather than positions within the record (`ai_01`, `ai_02`, …). Position
    /// is only unique *inside* one whiteboard, so every capture would contribute its own `ai_01` —
    /// useless the moment action items are gathered across meetings (the planned macOS "Action Items"
    /// view), or a single item needs a durable handle to carry a status change. A `UUID` also matches
    /// how the rest of the app mints identity (`WBWhiteboardSaveService.makeIDs()`).
    ///
    /// Mint **once per capture** and reuse across save retries, the same discipline as `makeIDs()` —
    /// re-minting per attempt would give the same task a different id on every try.
    static func make(from texts: [String]) -> [WBActionItem] {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { text in
                WBActionItem(
                    id: UUID().uuidString,
                    text: text,
                    status: statusUnknown
                )
            }
    }
}
