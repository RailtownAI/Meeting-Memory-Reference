//
//  WhiteboardAppApp.swift
//  WhiteboardApp
//
//  Created by Mark Su on 2026-07-24.
//

import SwiftUI
import WhiteboardCore

@main
struct WhiteboardAppApp: App {
    init() {
        WBLog.setup(level: .debug)
        WBLog.debug("📱WhiteboardiOS App started")
        configureConductrUploads()
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
    }
}
