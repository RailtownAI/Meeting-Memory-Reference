//
//  WBiOSShortcutVocabulary.swift
//  WhiteboardApp
//
//  Keeps the meeting names Siri knows for the Remember Whiteboard phrases up to date. iOS only:
//  macOS does not support App Shortcuts.
//

import AppIntents
import EventKit
import Foundation
import WhiteboardCore

/// Asks the system to re-read `WBiOSMeetingEntityQuery.suggestedEntities()`, the meetings a phrase
/// like "Save this whiteboard to Sprint planning in Meeting Memory" can name. The system reads
/// them only when the app calls `updateAppShortcutParameters()`.
///
/// Refreshes at launch, when the scene becomes active, after calendar access is granted, when the
/// calendar changes and when the day changes. Bursts (launch and activation together, a sync that
/// changes many events) are coalesced into one refresh. Without full calendar access the
/// suggestions are empty, so the refresh still succeeds. Never called from an intent's `perform()`.
@MainActor
enum WBiOSShortcutVocabulary {
    /// How long a request waits for more before refreshing.
    private static let debounce: Duration = .seconds(2)

    /// Kept alive so `.EKEventStoreChanged` is posted: EventKit only posts it while a store exists.
    private static let eventService = WBEventKitService()

    private static var pendingRefresh: Task<Void, Never>?
    private static var observers: [any NSObjectProtocol] = []

    /// Refreshes once now and again on every calendar or day change. Call once at launch.
    static func start() {
        if observers.isEmpty {
            // Touched here so the store exists from launch, whatever the access.
            _ = eventService
            observers = [
                observe(.EKEventStoreChanged, reason: "calendar changed"),
                observe(.NSCalendarDayChanged, reason: "day changed"),
            ]
        }
        refresh(reason: "launch")
    }

    /// Refreshes after `debounce`, replacing a refresh still waiting.
    static func refresh(reason: String) {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else {
                return
            }
            WBLog.info("🗣️ Refreshing the meeting names Siri knows (\(reason))")
            WBiOSMeetingMemoryShortcuts.updateAppShortcutParameters()
        }
    }

    private static func observe(_ name: Notification.Name, reason: String) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in
                refresh(reason: reason)
            }
        }
    }
}
