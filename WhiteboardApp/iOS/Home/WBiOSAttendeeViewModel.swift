import Observation
import UIKit
import WhiteboardCore

/// View model for one attendee chip: resolves the attendee's portrait from the user's
/// Contacts through the shared Core `WBContactPhotoService` (email first, then name),
/// reloading if the view is reused for a different attendee.
@Observable
final class WBiOSAttendeeViewModel {
    /// One service and cache for every chip — authorization is process-wide and resolved
    /// portraits are reused across the meeting card, picker, and re-renders.
    private static let photoService = WBContactPhotoService()
    private static let portraitCache = NSCache<NSString, UIImage>()

    private var loadedAttendeeID: String?

    private(set) var portrait: UIImage?

    /// Loads the portrait for `attendee`. The first lookup triggers the one-time system
    /// Contacts prompt; denied access or no matching contact resolves to `nil` — the view
    /// keeps its placeholder.
    func loadPortrait(for attendee: WBiOSAttendee) async {
        guard attendee.id != loadedAttendeeID else {
            return
        }
        loadedAttendeeID = attendee.id
        portrait = nil
        if let cachedPortrait = WBiOSAttendeeViewModel.portraitCache.object(
            forKey: attendee.id as NSString
        ) {
            portrait = cachedPortrait
            return
        }
        if WBiOSAttendeeViewModel.photoService.canRequestAccess {
            _ = try? await WBiOSAttendeeViewModel.photoService.requestAccess()
        }
        let data = await WBiOSAttendeeViewModel.photoService.photoThumbnailData(
            email: attendee.email,
            name: attendee.name
        )
        // A stale completion (the attendee changed again mid-flight) must not clobber the newer load.
        guard !Task.isCancelled, loadedAttendeeID == attendee.id else {
            return
        }
        guard let data, let image = UIImage(data: data) else {
            return
        }
        WBiOSAttendeeViewModel.portraitCache.setObject(image, forKey: attendee.id as NSString)
        portrait = image
    }
}
