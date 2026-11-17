//
//  WBiOSMeetingMemoryShortcuts.swift
//  WhiteboardApp
//
//  Siri phrases and Spotlight actions, available as soon as the app is installed. iOS only:
//  macOS does not support App Shortcuts.
//

import AppIntents

/// A phrase can only hold entity or enum parameters, so Siri asks for the question or the photo
/// after the phrase. Remember Whiteboard's meeting is an entity, so two of its phrases name it; the
/// values Siri learns for it are `WBiOSMeetingEntityQuery.suggestedEntities()`, refreshed by
/// `WBiOSShortcutVocabulary`. Without a meeting in the phrase, the photo goes to the current meeting.
struct WBiOSMeetingMemoryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WBAskMeetingMemoryIntent(),
            phrases: [
                "Ask \(.applicationName) about my whiteboards",
                "Ask \(.applicationName) about my meetings",
            ],
            shortTitle: "Ask About Meetings",
            systemImageName: "questionmark.bubble"
        )
        AppShortcut(
            intent: WBiOSRememberWhiteboardIntent(),
            phrases: [
                "Remember this whiteboard with \(.applicationName)",
                "Save this whiteboard to \(.applicationName)",
                "Save this whiteboard to \(\.$meeting) in \(.applicationName)",
                "Remember this whiteboard for \(\.$meeting) with \(.applicationName)",
            ],
            shortTitle: "Remember Whiteboard",
            systemImageName: "rectangle.and.pencil.and.ellipsis"
        )
    }
}
