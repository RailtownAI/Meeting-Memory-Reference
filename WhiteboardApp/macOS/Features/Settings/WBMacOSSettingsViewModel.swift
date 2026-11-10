import Observation
import WhiteboardCore

/// View model for `WBMacOSSettingsView`. Owns the API-key fields and their Keychain
/// persistence.
///
/// Each key is entered in a `SecureField`, saved to `WBKeychainStore`, then the field is
/// cleared; a per-key "is set" flag drives the checkmark. The stored values are never read
/// back into the UI.
///
/// The Mac reads with the retrieval PATs (`ENGINE_PAT`) for the whiteboard and calendar
/// rail engine servers, plus the Gemini key. It also *writes* now — editing a whiteboard's
/// action items re-ingests its record — so it takes the whiteboard ingestion token
/// (`ENGINE_TOKEN`) too; the calendar ingestion token stays iOS-only, since nothing on the
/// Mac writes calendar records. Deliberately a separate copy of the iOS settings view model
/// so the two UIs can diverge.
@Observable
final class WBMacOSSettingsViewModel {
    /// Draft text for the Gemini API key field.
    var geminiKey = ""

    /// Draft text for the Railtown Conductr API key field.
    var railtownConductrKey = ""

    /// Draft text for the whiteboard retrieval PAT (`ENGINE_PAT`) field.
    var enginePATWhiteboard = ""

    /// Draft text for the whiteboard ingestion token (`ENGINE_TOKEN`) field.
    var engineTokenWhiteboard = ""

    /// Draft text for the calendar retrieval PAT (`ENGINE_PAT`) field.
    var enginePATCalendar = ""

    /// Whether a Gemini API key is already stored.
    private(set) var isGeminiKeySet = false

    /// Whether a Railtown Conductr API key is already stored.
    private(set) var isRailtownConductrKeySet = false

    /// Whether the whiteboard ENGINE_PAT is already stored.
    private(set) var isEnginePATWhiteboardSet = false

    /// Whether the whiteboard ENGINE_TOKEN is already stored.
    private(set) var isEngineTokenWhiteboardSet = false

    /// Whether the calendar ENGINE_PAT is already stored.
    private(set) var isEnginePATCalendarSet = false

    /// Whether any field has draft text waiting to be saved.
    var hasUnsavedChanges: Bool {
        !geminiKey.isEmpty
            || !railtownConductrKey.isEmpty
            || !enginePATWhiteboard.isEmpty
            || !engineTokenWhiteboard.isEmpty
            || !enginePATCalendar.isEmpty
    }

    /// Saves every field that has draft text, clearing each on success.
    func saveAll() {
        saveGeminiKey()
        saveRailtownConductrKey()
        saveEnginePATWhiteboard()
        saveEngineTokenWhiteboard()
        saveEnginePATCalendar()
    }

    /// Refreshes the "is set" flags from the Keychain. Call when the window appears.
    func load() {
        isGeminiKeySet = WBKeychainStore.readGeminiAPIKey().isNotNilNorEmpty
        isRailtownConductrKeySet = WBKeychainStore.readRailtownConductrAPIKey().isNotNilNorEmpty
        isEnginePATWhiteboardSet = WBKeychainStore.readEnginePATWhiteboard().isNotNilNorEmpty
        isEngineTokenWhiteboardSet = WBKeychainStore.readEngineTokenWhiteboard().isNotNilNorEmpty
        isEnginePATCalendarSet = WBKeychainStore.readEnginePATCalendar().isNotNilNorEmpty
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
}
