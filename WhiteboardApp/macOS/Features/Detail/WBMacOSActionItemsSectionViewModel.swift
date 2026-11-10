import Foundation
import Observation
import WhiteboardCore

/// View model for a whiteboard's action items section: shows the items the shown whiteboard
/// arrived with, and persists the ones the user adds, edits, or deletes.
///
/// Every change holds its prompt open until the engine confirms it (ingest is queued, so a
/// write isn't stored when the request returns), and the list only ever shows what came back
/// stored.
///
/// Checking an item off is **local-only**, so it lasts as long as the whiteboard stays
/// shown: every item is ingested as "unknown" (`WBActionItem.statusUnknown`), and the wire
/// contract has no agreed done/open status to write back yet. Persisting the checkmark is a
/// follow-up once it does.
@Observable
final class WBMacOSActionItemsSectionViewModel {

    /// What the open prompt is asking. One sheet serves all three so they share the saving,
    /// error, and dismissal behavior — and so two prompts can never be up at once.
    enum Prompt: Identifiable {
        case add
        case edit(WBMacOSActionItem)
        case delete(WBMacOSActionItem)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let item): return "edit-\(item.id)"
            case .delete(let item): return "delete-\(item.id)"
            }
        }

        var isDelete: Bool {
            if case .delete = self {
                return true
            }
            return false
        }

        var title: String {
            switch self {
            case .add: return "Add Action Item"
            case .edit: return "Edit Action Item"
            case .delete: return "Delete Action Item?"
            }
        }
    }

    private let actionItemsProvider: WBMacOSActionItemsProviding

    /// Hands a stored change up to the detail, which writes it into the caches the section is
    /// rebuilt from — otherwise the next rebuild would show the pre-change list again.
    private let onItemsChanged: ([WBMacOSActionItem]) -> Void

    private var shownWhiteboardID: String?

    var items: [WBMacOSActionItem] = []

    /// The open prompt, if any. Cleared once its change is stored.
    var prompt: Prompt?

    /// Text being typed into the add / edit prompt.
    var draftText = ""

    /// Set while a change is being stored — prompts stay open and every entry point locks, so
    /// two writes can't race the same record.
    private(set) var isSaving = false

    /// Set when the last save failed, so the prompt can say so instead of closing as if it had
    /// worked.
    private(set) var saveErrorMessage: String?

    init(
        actionItemsProvider: WBMacOSActionItemsProviding,
        onItemsChanged: @escaping ([WBMacOSActionItem]) -> Void
    ) {
        self.actionItemsProvider = actionItemsProvider
        self.onItemsChanged = onItemsChanged
    }

    /// Whether the typed text is empty once trimmed — gates the prompt's confirm button so a
    /// blank row can't be added, or an existing one blanked.
    var isDraftBlank: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Shows `whiteboard`'s items. They ride along on the record, so this is a swap rather
    /// than a fetch; it also clears any state left from the previously shown whiteboard.
    func show(_ whiteboard: WBMacOSWhiteboard?) {
        shownWhiteboardID = whiteboard?.id
        items = whiteboard?.actionItems ?? []
        draftText = ""
        prompt = nil
        saveErrorMessage = nil
    }

    /// Opens the prompt to add a new item. Ignored while a save is in flight — every change is
    /// a read-modify-write of the whole record, so a second one started before the first lands
    /// would read the pre-change list and write back over it.
    func beginAdd() {
        guard !isSaving else {
            return
        }
        draftText = ""
        saveErrorMessage = nil
        prompt = .add
    }

    /// Opens the prompt seeded with `item`'s current wording. Ignored while a save is in
    /// flight, for the same reason as `beginAdd()`.
    func beginEdit(_ item: WBMacOSActionItem) {
        guard !isSaving else {
            return
        }
        draftText = item.text
        saveErrorMessage = nil
        prompt = .edit(item)
    }

    /// Asks for confirmation before removing `item` — deletion is not undoable. Ignored while
    /// a save is in flight, for the same reason as `beginAdd()`.
    func beginDelete(_ item: WBMacOSActionItem) {
        guard !isSaving else {
            return
        }
        saveErrorMessage = nil
        prompt = .delete(item)
    }

    /// Closes the prompt without changing anything. Ignored mid-save, so a change can't be
    /// abandoned while it is being stored.
    func cancelPrompt() {
        guard !isSaving else {
            return
        }
        draftText = ""
        saveErrorMessage = nil
        prompt = nil
    }

    /// Applies whatever the open prompt is asking, and closes it once the engine confirms the
    /// change. A failure leaves the prompt open with the reason — and, for add and edit, the
    /// typed text intact to retry.
    func submitPrompt() async {
        guard !isSaving, let prompt, let whiteboardID = shownWhiteboardID else {
            return
        }
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let didSave = await save(on: whiteboardID) { provider in
            switch prompt {
            case .add:
                return try await provider.addActionItem(text: text, toWhiteboardID: whiteboardID)
            case .edit(let item):
                return try await provider.updateActionItem(
                    id: item.id,
                    text: text,
                    onWhiteboardID: whiteboardID
                )
            case .delete(let item):
                return try await provider.deleteActionItem(
                    id: item.id,
                    fromWhiteboardID: whiteboardID
                )
            }
        }
        guard didSave else {
            return
        }
        draftText = ""
        self.prompt = nil
    }

    /// Runs a change through the provider and adopts the stored list, keeping the local
    /// checkmarks. A failed save leaves the list untouched and surfaces the reason.
    ///
    /// Returns whether the change was stored, so callers can keep the prompt open on failure.
    @discardableResult
    private func save(
        on whiteboardID: String,
        _ change: (WBMacOSActionItemsProviding) async throws -> [WBMacOSActionItem]
    ) async -> Bool {
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let savedItems = try await change(actionItemsProvider)
            // A stale completion (the whiteboard changed mid-save) must not clobber the
            // newer list.
            guard shownWhiteboardID == whiteboardID else {
                return false
            }
            let mergedItems = merging(savedItems)
            items = mergedItems
            onItemsChanged(mergedItems)
            return true
        } catch {
            WBLog.error("Couldn't save action items on whiteboard \(whiteboardID): \(error)")
            guard shownWhiteboardID == whiteboardID else {
                return false
            }
            saveErrorMessage = Self.message(for: error)
            return false
        }
    }

    /// What to show the user for a failed change.
    ///
    /// The app's own errors carry a written explanation (a missing ingestion token, a change that
    /// didn't show up in time) and are worth surfacing as-is. The SDKs' `RailengineError` is not a
    /// `LocalizedError`, so its `localizedDescription` is Foundation's placeholder — "The operation
    /// couldn't be completed. (Railengine.RailengineError error 2.)" — which tells the user
    /// nothing. Those become a plain sentence instead; the real error is in the log either way.
    private static func message(for error: Error) -> String {
        guard let description = (error as? LocalizedError)?.errorDescription else {
            return "Couldn't save the change. Check your connection and try again."
        }
        return description
    }

    /// The engine's list, keeping whatever the user has checked off here. Every stored item
    /// comes back as not-done (status is always "unknown" on the wire), so adopting the list
    /// as-is would silently uncheck the boxes ticked since the whiteboard opened.
    private func merging(_ savedItems: [WBMacOSActionItem]) -> [WBMacOSActionItem] {
        let doneIDs = Set(items.filter(\.isDone).map(\.id))
        return savedItems.map { item in
            var merged = item
            merged.isDone = merged.isDone || doneIDs.contains(item.id)
            return merged
        }
    }
}
