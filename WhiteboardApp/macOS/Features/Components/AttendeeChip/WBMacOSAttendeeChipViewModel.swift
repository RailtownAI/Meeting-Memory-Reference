import AppKit
import Observation

/// View model for one attendee chip: resolves the attendee's avatar through the attendee
/// image provider, reloading if the chip is reused for a different attendee.
@Observable
final class WBMacOSAttendeeChipViewModel {
    private let imageProvider: WBMacOSAttendeeImageProviding
    private var loadedAttendeeID: String?

    private(set) var avatar: NSImage?

    init(imageProvider: WBMacOSAttendeeImageProviding) {
        self.imageProvider = imageProvider
    }

    /// Loads the avatar for `attendee`. No photo resolves to `nil` — the chip keeps its
    /// initials.
    func loadAvatar(for attendee: WBMacOSAttendee) async {
        guard attendee.id != loadedAttendeeID else {
            return
        }
        loadedAttendeeID = attendee.id
        avatar = nil
        let loadedAvatar = await imageProvider.avatar(for: attendee)
        guard !Task.isCancelled else {
            return
        }
        // A stale completion (the attendee changed again mid-flight) must not clobber the newer load.
        guard loadedAttendeeID == attendee.id else {
            return
        }
        avatar = loadedAvatar
    }
}
