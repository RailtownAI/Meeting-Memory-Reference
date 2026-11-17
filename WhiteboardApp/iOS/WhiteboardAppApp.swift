//
//  WhiteboardAppApp.swift
//  WhiteboardApp
//
//  Created by Mark Su on 2026-07-24.
//

import AppIntents
import SwiftUI
import WhiteboardCore

@main
struct WhiteboardAppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WBLog.setup(level: .debug)
        WBLog.debug("📱WhiteboardiOS App started")
        configureConductrUploads()
        registerIntentDependencies()
        WBiOSShortcutVocabulary.start()
    }

    /// The services the Siri and Shortcuts actions reach through `@Dependency`.
    private func registerIntentDependencies() {
        AppDependencyManager.shared.add(dependency: WBPromptSearchService())
        AppDependencyManager.shared.add(dependency: WBWhiteboardRecordStore())
        AppDependencyManager.shared.add(dependency: WBEventKitService())
        AppDependencyManager.shared.add(dependency: WBiOSMeetingSyncService())
    }

    /// Hands the stored Conductr key to both uploaders — agent-run traces and error logs —
    /// which cache it rather than reading the
    /// Keychain itself. `WBiOSSettingsViewModel` repeats this when the key changes, so one entered
    /// mid-session takes effect without a relaunch.
    private func configureConductrUploads() {
        guard let apiKey = WBKeychainStore.readRailtownConductrAPIKey(), !apiKey.isEmpty else {
            WBLog.warning("⚠️🔗 No Conductr API key stored — agent-run and error-log uploads stay off until one is saved")
            return
        }
        WBRailtownLoggerSetup.configure(apiKey: apiKey)
    }

    var body: some Scene {
        WindowGroup {
            WBiOSRootTabView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Catches calendar access granted in Settings, and meetings added while away.
            if phase == .active {
                WBiOSShortcutVocabulary.refresh(reason: "scene active")
            }
        }
    }
}
