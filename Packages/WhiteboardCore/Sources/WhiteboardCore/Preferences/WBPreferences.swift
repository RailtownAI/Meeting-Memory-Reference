//
//  WBPreferences.swift
//  WhiteboardCore
//

import Foundation
import RailtracksSwift

/// User-changeable settings that aren't secrets, stored in `UserDefaults`.
///
/// Deliberately not `WBKeychainStore`: nothing here is a credential, and that store writes items as
/// iCloud-**synchronizable**, so a value typed on one device would appear on every other device
/// signed into the same account. A model name is a per-device choice — often a deliberately broken
/// one, while testing what a failure looks like — and shouldn't travel.
///
/// Every member is computed, so there is no mutable state to isolate: callers read it from whatever
/// thread they're on, including off the main actor inside an agent service.
public enum WBPreferences {
    /// Model the capture-analysis agents run on when the user hasn't chosen one.
    public static let defaultAnalysisModelID = RTSGeminiModelID.gemini3Flash.modelIDString

    /// Models offered in Settings, in the order they're listed there.
    ///
    /// Hand-listed because `RTSGeminiModelID` is a bare enum with no `CaseIterable` conformance —
    /// there is nothing to iterate. That's no loss: this is a short menu of the tiers worth
    /// switching between, and anything outside it goes in through the custom field.
    public static let analysisModelChoices: [String] = [
        defaultAnalysisModelID,
        RTSGeminiModelID.gemini25Flash.modelIDString,
        RTSGeminiModelID.gemini25Pro.modelIDString,
        RTSGeminiModelID.flashLatest.modelIDString
    ]

    /// The model the user chose, or `nil` when they haven't — what Settings resolves its picker
    /// from. Blank storage reads as `nil`, so a cleared field can't leave an empty model behind.
    public static var analysisModelIDOverride: String? {
        let stored = defaults.string(forKey: analysisModelIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stored.isNotNilNorEmpty else {
            return nil
        }
        return stored
    }

    /// The model to actually call. Read at call time rather than cached, so a change in Settings
    /// applies to the next run without a relaunch.
    public static var analysisModelID: String {
        analysisModelIDOverride ?? defaultAnalysisModelID
    }

    /// Stores the user's choice. `nil` or blank clears it, which is how Settings gets back to the
    /// default — there's no separate "unset" call to keep in step with this one.
    public static func writeAnalysisModelID(_ modelID: String?) {
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            defaults.removeObject(forKey: analysisModelIDKey)
            return
        }
        defaults.set(trimmed, forKey: analysisModelIDKey)
    }

    /// Namespaced like the Keychain service id, so the app's defaults stay distinguishable from
    /// anything a framework writes into the same suite.
    private static let analysisModelIDKey = "ai.railtown.whiteboard.analysis-model-id"

    private static var defaults: UserDefaults {
        .standard
    }
}
