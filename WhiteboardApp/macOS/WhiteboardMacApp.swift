//
//  WhiteboardMacApp.swift
//  WhiteboardMac
//
//  Created by Mark Su on 2026-07-24.
//

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
