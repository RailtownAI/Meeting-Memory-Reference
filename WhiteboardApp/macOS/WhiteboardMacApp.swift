//
//  WhiteboardMacApp.swift
//  WhiteboardMac
//
//  Created by Mark Su on 2026-07-24.
//

import AppIntents
import SwiftUI
import WhiteboardCore

@main
struct WhiteboardMacApp: App {
    private let selectionManager: WBMacOSSelectionManager
    private let sessionManager: WBMacOSAnswerSessionManager
    private let meetingDetailManager: WBMacOSMeetingDetailManager

    init() {
        WBLog.setup()
        Self.configureConductrUploads()
        Self.registerIntentDependencies()
        let selectionManager = WBMacOSSelectionManager()
        self.selectionManager = selectionManager
        sessionManager = WBMacOSAnswerSessionManager(
            answerProvider: WBMacOSAgentAnswerProvider(),
            selectionManager: selectionManager
        )
        meetingDetailManager = WBMacOSMeetingDetailManager(
            meetingDetailProvider: WBMacOSEventKitMeetingDetailProvider(),
            meetingWhiteboardsProvider: WBMacOSMeetingWhiteboardsProvider()
        )
        // Captures come from the iPhone; indexing them here puts them in this Mac's Spotlight and
        // Siri.
        Task {
            await WBWhiteboardSpotlight.syncLatest()
        }
    }

    /// Hands the stored Conductr key to both uploaders — agent-run traces and error logs —
    /// which cache it rather than reading the
    /// Keychain itself. `WBMacOSSettingsViewModel` repeats this when the key changes, so one entered
    /// mid-session takes effect without a relaunch. `static` because it runs before the stored
    /// managers are initialized.
    private static func configureConductrUploads() {
        guard let apiKey = WBKeychainStore.readRailtownConductrAPIKey(), !apiKey.isEmpty else {
            WBLog.warning("⚠️🔗 No Conductr API key stored — agent-run and error-log uploads stay off until one is saved")
            return
        }
        WBRailtownLoggerSetup.configure(apiKey: apiKey)
    }

    /// The services the Siri and Shortcuts actions reach through `@Dependency`. `static` because it
    /// runs before the stored managers are initialized.
    private static func registerIntentDependencies() {
        AppDependencyManager.shared.add(dependency: WBPromptSearchService())
        AppDependencyManager.shared.add(dependency: WBWhiteboardRecordStore())
        AppDependencyManager.shared.add(dependency: WBEventKitService())
    }

    var body: some Scene {
        WindowGroup {
            WBMacOSRootView(
                manager: selectionManager,
                sessionManager: sessionManager,
                meetingDetailManager: meetingDetailManager,
                imageProvider: WBMacOSICloudWhiteboardImageProvider(),
                attendeeImageProvider: WBMacOSContactsAttendeeImageProvider(),
                actionItemsProvider: WBMacOSActionItemsProvider(),
                scheduleEventsProvider: WBMacOSEventKitScheduleEventsProvider(),
                eventWhiteboardsProvider: WBMacOSEventWhiteboardsProvider()
            )
        }

        Settings {
            WBMacOSSettingsView()
        }
    }
}
