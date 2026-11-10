import Foundation
import Security

/// Stores and retrieves API keys in the Keychain. Shared by the iOS and macOS apps.
///
/// Every query sets `kSecUseDataProtectionKeychain` so behavior is identical on iOS and macOS.
/// Items are written as **synchronizable** (iCloud Keychain) into the apps' shared keychain
/// access group — writes land in the first group listed in the target's
/// `keychain-access-groups` entitlement — so a key saved on one device is readable by the
/// other app on the user's other devices. Requires both apps to be signed by the same team
/// and the user to have iCloud Keychain enabled.
public enum WBKeychainStore {
    /// Keychain service namespace for all WhiteboardApp credentials.
    public static let service = "ai.railtown.whiteboard"

    /// Account name for the Gemini API key.
    public static let geminiAPIKeyAccount = "gemini-api-key"

    /// Account name for the Railtown Conductr API key — the base64 blob from the Conductr
    /// dashboard that `RailtownClient` decodes into its host/org/project/secret/environment.
    public static let railtownConductrAPIKeyAccount = "railtown-conductr-api-key"

    /// Account name for the whiteboard rail engine ingestion token (`ENGINE_TOKEN`).
    public static let engineTokenWhiteboardAccount = "engine-token-whiteboard"

    /// Account name for the whiteboard rail engine retrieval PAT (`ENGINE_PAT`, expiring).
    public static let enginePATWhiteboardAccount = "engine-pat-whiteboard"

    /// Account name for the calendar rail engine ingestion token (`ENGINE_TOKEN`).
    public static let engineTokenCalendarAccount = "engine-token-calendar"

    /// Account name for the calendar rail engine retrieval PAT (`ENGINE_PAT`, expiring).
    public static let enginePATCalendarAccount = "engine-pat-calendar"

    /// Reads the string value stored for the given account, or `nil` if none exists.
    /// Matches both synchronizable and legacy device-local items.
    public static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Inserts or updates the value for the given account. Returns whether the write succeeded.
    ///
    /// Deletes any existing item first (the synchronizable attribute cannot be changed via
    /// `SecItemUpdate`), then adds a synchronizable item with `AfterFirstUnlock`
    /// accessibility — the device-only accessibility classes refuse to sync.
    @discardableResult
    public static func write(_ value: String, account: String) -> Bool {
        delete(account: account)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8)
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Deletes any value stored for the given account, synchronizable or device-local.
    /// Returns whether the item is now absent. Deleting a synchronizable item removes it
    /// from all of the user's devices.
    @discardableResult
    public static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - API key convenience

public extension WBKeychainStore {
    /// The stored Gemini API key, or `nil` if none is set.
    static func readGeminiAPIKey() -> String? {
        read(account: geminiAPIKeyAccount)
    }

    /// Stores the Gemini API key. Returns whether the write succeeded.
    @discardableResult
    static func writeGeminiAPIKey(_ key: String) -> Bool {
        write(key, account: geminiAPIKeyAccount)
    }

    /// The stored Railtown Conductr API key, or `nil` if none is set.
    static func readRailtownConductrAPIKey() -> String? {
        read(account: railtownConductrAPIKeyAccount)
    }

    /// Stores the Railtown Conductr API key. Returns whether the write succeeded.
    @discardableResult
    static func writeRailtownConductrAPIKey(_ key: String) -> Bool {
        write(key, account: railtownConductrAPIKeyAccount)
    }

    /// The stored whiteboard ingestion token (`ENGINE_TOKEN`), or `nil` if none is set.
    static func readEngineTokenWhiteboard() -> String? {
        read(account: engineTokenWhiteboardAccount)
    }

    /// Stores the whiteboard ingestion token (`ENGINE_TOKEN`). Returns whether the write succeeded.
    @discardableResult
    static func writeEngineTokenWhiteboard(_ token: String) -> Bool {
        write(token, account: engineTokenWhiteboardAccount)
    }

    /// The stored whiteboard retrieval PAT (`ENGINE_PAT`), or `nil` if none is set.
    static func readEnginePATWhiteboard() -> String? {
        read(account: enginePATWhiteboardAccount)
    }

    /// Stores the whiteboard retrieval PAT (`ENGINE_PAT`). Returns whether the write succeeded.
    @discardableResult
    static func writeEnginePATWhiteboard(_ pat: String) -> Bool {
        write(pat, account: enginePATWhiteboardAccount)
    }

    /// The stored calendar ingestion token (`ENGINE_TOKEN`), or `nil` if none is set.
    static func readEngineTokenCalendar() -> String? {
        read(account: engineTokenCalendarAccount)
    }

    /// Stores the calendar ingestion token (`ENGINE_TOKEN`). Returns whether the write succeeded.
    @discardableResult
    static func writeEngineTokenCalendar(_ token: String) -> Bool {
        write(token, account: engineTokenCalendarAccount)
    }

    /// The stored calendar retrieval PAT (`ENGINE_PAT`), or `nil` if none is set.
    static func readEnginePATCalendar() -> String? {
        read(account: enginePATCalendarAccount)
    }

    /// Stores the calendar retrieval PAT (`ENGINE_PAT`). Returns whether the write succeeded.
    @discardableResult
    static func writeEnginePATCalendar(_ pat: String) -> Bool {
        write(pat, account: enginePATCalendarAccount)
    }
}
