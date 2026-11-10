import Contacts
import Foundation

/// Read-only Contacts access shared by the iOS and macOS apps — resolves an event attendee
/// to their contact photo.
///
/// EventKit exposes no participant photos; the supported path is matching the attendee
/// against the user's Contacts and reading the matching contact's thumbnail. Lookups match
/// by email first (from the attendee's `mailto:` URL), then by full name — so only people
/// in the user's Contacts, with a photo set, resolve. Callers show an initials avatar for
/// everyone else.
///
/// Contacts access is its own permission, separate from calendar access: the app target
/// needs a `NSContactsUsageDescription` (and the address-book sandbox entitlement on
/// macOS), and the first `requestAccess()` call shows the system prompt.
///
/// An actor so the `CNContactStore`'s synchronous fetches run off the callers' threads.
public actor WBContactPhotoService {
    /// Mirrors `WBEventKitService.WBEventKitError` so a denied permission has a type to be reported
    /// under. Nothing here *throws* it — a denial reaches callers as `false` from `requestAccess()`
    /// or a `nil` thumbnail — but `WBPermissionReporter` needs an error to hand the platform, and an
    /// error owned by this service groups better than one invented at the call site.
    public enum WBContactPhotoError: LocalizedError, CustomStringConvertible {
        case accessDenied

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Contacts access is not granted — allow access in Settings."
            }
        }

        /// See `WBEventKitService.WBEventKitError.description` — without this, `String(describing:)`
        /// renders the bare case name, which is what reaches Conductr's exception headline.
        public var description: String {
            errorDescription ?? "Contacts access is not granted."
        }
    }

    private let store = CNContactStore()

    public init() {}

    /// Whether Contacts access is granted. `.limited` (the user shared a subset) counts —
    /// lookups simply miss for contacts outside the shared set.
    ///
    /// Nonisolated: this reads process-wide Contacts state, not actor state, so callers can
    /// check it synchronously.
    public nonisolated var isAccessAuthorized: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    /// Whether the user hasn't been asked for Contacts access yet — i.e. `requestAccess()`
    /// would show the system prompt rather than silently return the standing denial.
    public nonisolated var canRequestAccess: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .notDetermined
    }

    /// Prompts for Contacts access (the system shows its dialog on the first call only).
    /// Returns whether access is granted.
    ///
    /// A refusal is reported to the Railtown platform — see `WBPermissionReporter`, which keeps it
    /// to one report per launch. Nothing else changes: callers still get `false`, and an attendee
    /// with no reachable photo still falls back to an initials avatar.
    public func requestAccess() async throws -> Bool {
        let canPrompt = canRequestAccess
        let isGranted = try await store.requestAccess(for: .contacts)
        if !isGranted {
            WBPermissionReporter.reportDenied(
                .contacts,
                canPrompt ? .deniedAtPrompt : .deniedBeforeLaunch
            )
        }
        return isGranted
    }

    /// A person's contact photo thumbnail (the pre-cropped square avatar), matched by
    /// `email` first, then by full `name` — or `nil` when access isn't granted, no contact
    /// matches, or the matching contacts have no photo. Never prompts.
    public func photoThumbnailData(email: String?, name: String?) -> Data? {
        guard isAccessAuthorized else {
            // The standing-denial path: this never prompts, so reaching here means access was
            // refused before now — either in an earlier launch or at a prompt already reported.
            WBPermissionReporter.reportDenied(.contacts, .deniedBeforeLaunch)
            return nil
        }
        if let email, !email.isEmpty,
           let data = firstThumbnail(matching: CNContact.predicateForContacts(matchingEmailAddress: email)) {
            return data
        }
        if let name, !name.isEmpty,
           let data = firstThumbnail(matching: CNContact.predicateForContacts(matchingName: name)) {
            return data
        }
        return nil
    }

    /// Convenience for an event attendee: matches by the `mailto:` email, then the name.
    public func photoThumbnailData(for attendee: WBEventAttendee) -> Data? {
        photoThumbnailData(email: attendee.emailAddress, name: attendee.name)
    }
}

private extension WBContactPhotoService {

    /// The first matching contact's thumbnail. Matches without a photo are skipped so a
    /// photo-less duplicate can't shadow the contact card that carries one.
    func firstThumbnail(matching predicate: NSPredicate) -> Data? {
        do {
            let contacts = try store.unifiedContacts(
                matching: predicate,
                keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor]
            )
            return contacts.lazy.compactMap(\.thumbnailImageData).first
        } catch {
            WBLog.debug("Contact photo lookup failed: \(error)")
            return nil
        }
    }
}
