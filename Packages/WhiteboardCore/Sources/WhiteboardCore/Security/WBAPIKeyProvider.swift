import Foundation

/// The LLM providers the app can prompt an API key for.
///
/// Only Gemini is supported for now. To add a provider, add a case here plus a matching Keychain
/// slot on `WBKeychainStore`. (The rail engine credentials are *not* providers — they're separate
/// service keys, accessed directly via `WBKeychainStore`'s engine-token / engine-PAT methods.)
public enum WBAPIKeyProvider: CaseIterable, Sendable {
    case gemini

    /// Human-readable provider name for display in a key-setup UI.
    public var displayName: String {
        switch self {
        case .gemini:
            return "Gemini"
        }
    }

    /// Placeholder hint for the key-entry field. Google AI Studio issues more than one key format
    /// (e.g. "AIza…", "AQ.…"), so this hints the source rather than a specific prefix.
    public var keyPlaceholder: String {
        switch self {
        case .gemini:
            return "Google AI Studio API key"
        }
    }

    /// Reads this provider's key from the Keychain.
    public func readKey() -> String? {
        switch self {
        case .gemini:
            return WBKeychainStore.readGeminiAPIKey()
        }
    }

    /// Stores this provider's key in the Keychain. Returns whether the write succeeded.
    @discardableResult
    public func writeKey(_ key: String) -> Bool {
        switch self {
        case .gemini:
            return WBKeychainStore.writeGeminiAPIKey(key)
        }
    }
}
