import Foundation
import Observation
import WhiteboardCore

/// View model for `WBiOSSettingsView`. Owns the API-key fields and their Keychain persistence.
///
/// Each key is entered in a `SecureField`, saved to `WBKeychainStore`, then the field is cleared;
/// a per-key "is set" flag drives the checkmark. The stored values are never read back into the UI.
///
/// There are two rail engine servers — whiteboard and calendar — each with an ingestion token
/// (`ENGINE_TOKEN`) and a retrieval PAT (`ENGINE_PAT`), so four engine keys, plus the Gemini key and
/// the Railtown Conductr key that `RailtownClient` needs to upload agent-run JSON.
@Observable
@MainActor
final class WBiOSSettingsViewModel {
    /// Draft text for the Gemini API key field.
    var geminiKey = ""

    /// Draft text for the Railtown Conductr API key field.
    var railtownConductrKey = ""

    /// Draft text for the whiteboard ingestion token (`ENGINE_TOKEN`) field.
    var engineTokenWhiteboard = ""

    /// Draft text for the whiteboard retrieval PAT (`ENGINE_PAT`) field.
    var enginePATWhiteboard = ""

    /// Draft text for the calendar ingestion token (`ENGINE_TOKEN`) field.
    var engineTokenCalendar = ""

    /// Draft text for the calendar retrieval PAT (`ENGINE_PAT`) field.
    var enginePATCalendar = ""

    /// Whether a Gemini API key is already stored.
    private(set) var isGeminiKeySet = false

    /// Whether a Railtown Conductr API key is already stored.
    private(set) var isRailtownConductrKeySet = false

    /// Whether the whiteboard ENGINE_TOKEN is already stored.
    private(set) var isEngineTokenWhiteboardSet = false

    /// Whether the whiteboard ENGINE_PAT is already stored.
    private(set) var isEnginePATWhiteboardSet = false

    /// Whether the calendar ENGINE_TOKEN is already stored.
    private(set) var isEngineTokenCalendarSet = false

    /// Whether the calendar ENGINE_PAT is already stored.
    private(set) var isEnginePATCalendarSet = false

    /// Phase of the delete-all modal.
    enum DeletePhase {
        case deleting
        case done(WBDeleteAllResult)
    }

    /// Whether the delete-all confirmation alert is shown.
    var isConfirmingDelete = false

    /// Non-nil drives the locking delete modal: `.deleting` shows a spinner, `.done` shows the counts.
    private(set) var deletePhase: DeletePhase?

    private let deleteService = WBDeleteAllService()

    /// `tag` for the picker's "Custom…" row. Safe as a sentinel because a real value is a model id
    /// the provider puts in a URL path, which this isn't.
    static let customAnalysisModelTag = "__custom__"

    /// Which row the model picker has selected: a value from `WBPreferences.analysisModelChoices`,
    /// or `customAnalysisModelTag`.
    var analysisModelSelection = WBPreferences.defaultAnalysisModelID

    /// Draft text for the custom model field, used only while "Custom…" is selected.
    ///
    /// Unlike the key fields this round-trips — `load()` puts a stored custom value back on screen
    /// rather than blanking it. A key is write-only because reading one back is a leak; a model name
    /// is something the user has to be able to see to know what they set, especially when what they
    /// set is deliberately broken.
    var customAnalysisModelID = ""

    /// Whether a model is stored, i.e. the app isn't on the default. Mirrored into observable state
    /// because Observation can't track `UserDefaults`, so reading `WBPreferences` from the view
    /// wouldn't redraw "Use Default" when this changes.
    private(set) var hasAnalysisModelOverride = false

    /// Whether the picker is on "Custom…", which is what reveals the text field.
    var isCustomAnalysisModelSelected: Bool {
        analysisModelSelection == Self.customAnalysisModelTag
    }

    /// Whether Save has something to store. Only the custom row can be incomplete — a picked model
    /// is always a whole value.
    var canSaveAnalysisModel: Bool {
        guard isCustomAnalysisModelSelected else {
            return true
        }
        return !customAnalysisModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Refreshes the "is set" flags from the Keychain. Call when the screen appears.
    func load() {
        isGeminiKeySet = WBKeychainStore.readGeminiAPIKey().isNotNilNorEmpty
        isRailtownConductrKeySet = WBKeychainStore.readRailtownConductrAPIKey().isNotNilNorEmpty
        isEngineTokenWhiteboardSet = WBKeychainStore.readEngineTokenWhiteboard().isNotNilNorEmpty
        isEnginePATWhiteboardSet = WBKeychainStore.readEnginePATWhiteboard().isNotNilNorEmpty
        isEngineTokenCalendarSet = WBKeychainStore.readEngineTokenCalendar().isNotNilNorEmpty
        isEnginePATCalendarSet = WBKeychainStore.readEnginePATCalendar().isNotNilNorEmpty
        loadAnalysisModel()
    }

    /// Saves the picked model, or the typed one when the picker is on "Custom…".
    ///
    /// Re-reads afterwards rather than assuming what was stored: `WBPreferences` trims and treats
    /// blank as unset, and the screen should show what actually took effect.
    func saveAnalysisModel() {
        guard canSaveAnalysisModel else {
            return
        }
        let modelID = isCustomAnalysisModelSelected
            ? customAnalysisModelID
            : analysisModelSelection
        WBPreferences.writeAnalysisModelID(modelID)
        WBLog.debug("⚙️ Summarize model set to \(WBPreferences.analysisModelID)")
        loadAnalysisModel()
    }

    /// Drops the stored model so the built-in default applies again — the way back from a model
    /// that doesn't work, without having to remember what the default was.
    func resetAnalysisModel() {
        WBPreferences.writeAnalysisModelID(nil)
        WBLog.debug("⚙️ Summarize model reset to default")
        loadAnalysisModel()
    }

    /// Puts the stored model on screen. A known model selects its row; anything else — including a
    /// deliberately broken value — selects "Custom…" and fills the field, so it can be read and
    /// corrected instead of only overwritten.
    private func loadAnalysisModel() {
        let stored = WBPreferences.analysisModelIDOverride
        hasAnalysisModelOverride = stored != nil
        let modelID = stored ?? WBPreferences.defaultAnalysisModelID
        if WBPreferences.analysisModelChoices.contains(modelID) {
            analysisModelSelection = modelID
            customAnalysisModelID = ""
        } else {
            analysisModelSelection = Self.customAnalysisModelTag
            customAnalysisModelID = modelID
        }
    }

    /// Saves the Gemini key, then clears the field on success.
    func saveGeminiKey() {
        guard !geminiKey.isEmpty else {
            return
        }
        if WBKeychainStore.writeGeminiAPIKey(geminiKey) {
            isGeminiKeySet = true
            geminiKey = ""
        }
    }

    /// Saves the Railtown Conductr key, then clears the field on success.
    func saveRailtownConductrKey() {
        guard !railtownConductrKey.isEmpty else {
            return
        }
        if WBKeychainStore.writeRailtownConductrAPIKey(railtownConductrKey) {
            // Push it straight into the uploaders, which cache credentials rather than reading the
            // Keychain — without this the new key would sit unused until the next launch.
            WBRailtownLoggerSetup.configure(apiKey: railtownConductrKey)
            isRailtownConductrKeySet = true
            railtownConductrKey = ""
        }
    }

    /// Saves the whiteboard ENGINE_TOKEN, then clears the field on success.
    func saveEngineTokenWhiteboard() {
        guard !engineTokenWhiteboard.isEmpty else {
            return
        }
        if WBKeychainStore.writeEngineTokenWhiteboard(engineTokenWhiteboard) {
            isEngineTokenWhiteboardSet = true
            engineTokenWhiteboard = ""
        }
    }

    /// Saves the whiteboard ENGINE_PAT, then clears the field on success.
    func saveEnginePATWhiteboard() {
        guard !enginePATWhiteboard.isEmpty else {
            return
        }
        if WBKeychainStore.writeEnginePATWhiteboard(enginePATWhiteboard) {
            isEnginePATWhiteboardSet = true
            enginePATWhiteboard = ""
        }
    }

    /// Saves the calendar ENGINE_TOKEN, then clears the field on success.
    func saveEngineTokenCalendar() {
        guard !engineTokenCalendar.isEmpty else {
            return
        }
        if WBKeychainStore.writeEngineTokenCalendar(engineTokenCalendar) {
            isEngineTokenCalendarSet = true
            engineTokenCalendar = ""
        }
    }

    /// Saves the calendar ENGINE_PAT, then clears the field on success.
    func saveEnginePATCalendar() {
        guard !enginePATCalendar.isEmpty else {
            return
        }
        if WBKeychainStore.writeEnginePATCalendar(enginePATCalendar) {
            isEnginePATCalendarSet = true
            enginePATCalendar = ""
        }
    }

    /// Runs the delete-all: shows the locking modal, deletes all stores best-effort, then the counts.
    /// Credentials in the Keychain are left intact — this clears data, not keys.
    func confirmDeleteAll() {
        deletePhase = .deleting
        Task {
            let result = await deleteService.deleteAll()
            deletePhase = .done(result)
        }
    }

    /// Dismisses the delete result modal.
    func dismissDeleteResult() {
        deletePhase = nil
    }
}
