//
//  WBPermissionReporter.swift
//  WhiteboardCore
//

import Foundation
import RailtownLogger

/// Reports a denied system permission to the Railtown platform.
///
/// A denial isn't an error anywhere else in this app. EventKit and Contacts both return `false`
/// rather than throwing, and the screens treat that as an ordinary outcome — a permission message on
/// Home, an initials avatar in place of a portrait. This is the one place that treats it as
/// something worth recording, so the platform can show why an install stopped producing data.
///
/// **At most one report per permission per launch.** The screens re-check access every time they
/// appear, and Home re-checks on every pull-to-refresh, so reporting each observation would file the
/// same standing denial over and over. The one report carries how the denial happened:
/// `.deniedAtPrompt` when the user has just refused the system dialog, `.deniedBeforeLaunch` when it
/// was already refused and no dialog appeared.
///
/// Callable from anywhere — the calls live inside `WBEventKitService` and `WBContactPhotoService`,
/// which are actors, so this is lock-guarded rather than actor-isolated: an `await` would be
/// unavailable in the synchronous paths that need it (`photoThumbnailData` is not `async`).
public enum WBPermissionReporter {
    /// Permissions this reports on. Camera is deliberately absent: its denial already has a screen
    /// of its own, and it isn't part of what the calendar and contacts data path needs.
    public enum Permission: String, Sendable {
        case calendar
        case contacts
    }

    /// How the denial came about — the one piece of context a standing `false` doesn't carry.
    public enum Denial: String {
        /// The system dialog appeared during this check and the user refused it.
        case deniedAtPrompt = "denied-at-prompt"
        /// Access was already refused, so no dialog appeared.
        case deniedBeforeLaunch = "denied-before-launch"
    }

    /// Guards `reportedPermissions`, which is touched from whichever thread hit the denial.
    private static let lock = NSLock()

    // Only ever read or written under `lock`.
    nonisolated(unsafe) private static var reportedPermissions: Set<Permission> = []

    /// Records a denial, at most once per permission per launch. Safe to call from every access
    /// check — that's the point of the guard.
    public static func reportDenied(_ permission: Permission, _ denial: Denial) {
        lock.lock()
        let isFirstReport = reportedPermissions.insert(permission).inserted
        lock.unlock()
        guard isFirstReport else {
            return
        }
        let name = permission.rawValue
        let cause = denial.rawValue
        WBLog.error("🚫 \(name) access denied (\(cause))")
        // Reported as configured-or-not rather than deferred: the apps configure the logger in their
        // `App` init, before any view can check a permission, so an unconfigured logger here means
        // no Conductr key is stored — a setup problem to say out loud, not one to retry around.
        guard RailtownLogger.isConfigured else {
            WBLog.warning("⚠️🔗 Railtown isn't configured — the \(name) denial stays local")
            return
        }
        RailtownLogger.capture(
            error(for: permission),
            message: "\(raw: name) access denied",
            properties: ["Permission": name, "Denial": cause]
        )
    }

    /// The owning service's own error for that denial, so these group in the platform under the
    /// types the rest of the app uses rather than one invented here.
    private static func error(for permission: Permission) -> any Error {
        switch permission {
        case .calendar:
            return WBEventKitService.WBEventKitError.accessDenied
        case .contacts:
            return WBContactPhotoService.WBContactPhotoError.accessDenied
        }
    }
}
