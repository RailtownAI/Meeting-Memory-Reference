import AppKit
import WhiteboardCore

/// Provides the avatar photo for a meeting attendee.
///
/// Returns `nil` when no photo can be resolved — callers keep their initials avatar.
protocol WBMacOSAttendeeImageProviding {
    func avatar(for attendee: WBMacOSAttendee) async -> NSImage?
}

/// Real avatar provider: matches the attendee against the user's Contacts through the shared
/// `WBContactPhotoService` (email first, then name), decoding the contact's thumbnail into
/// an `NSImage`. Only attendees in the user's Contacts with a photo resolve — everyone else
/// stays on initials.
///
/// The first lookup triggers the one-time system Contacts prompt; once denied, lookups
/// resolve to `nil` without prompting again.
///
/// Decoded avatars are cached (shared across instances — the provider is a value type that's
/// recreated freely) so list re-renders don't re-query Contacts.
struct WBMacOSContactsAttendeeImageProvider: WBMacOSAttendeeImageProviding {
    private static let avatarCache = NSCache<NSString, NSImage>()

    private let photoService = WBContactPhotoService()

    func avatar(for attendee: WBMacOSAttendee) async -> NSImage? {
        if let cachedAvatar = WBMacOSContactsAttendeeImageProvider.avatarCache.object(
            forKey: attendee.id as NSString
        ) {
            return cachedAvatar
        }
        if photoService.canRequestAccess {
            _ = try? await photoService.requestAccess()
        }
        guard let data = await photoService.photoThumbnailData(
            email: attendee.email,
            name: attendee.displayName
        ) else {
            return nil
        }
        guard let avatar = NSImage(data: data) else {
            return nil
        }
        WBMacOSContactsAttendeeImageProvider.avatarCache.setObject(avatar, forKey: attendee.id as NSString)
        return avatar
    }
}
