import Foundation

/// A meeting attendee as the attendee chips render one — the display name plus the email
/// the avatar lookup keys on.
///
/// App-local model: mapped from EventKit's participants at the provider layer; personal
/// details never travel through railengine.
struct WBMacOSAttendee: Identifiable, Hashable {
    let displayName: String
    let email: String?

    var id: String {
        email ?? displayName
    }
}
