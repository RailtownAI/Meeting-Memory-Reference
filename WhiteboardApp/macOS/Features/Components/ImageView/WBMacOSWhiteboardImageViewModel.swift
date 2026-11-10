import AppKit
import Observation

/// View model for one whiteboard photo: resolves the image id it is asked to show through
/// the image provider, reloading whenever the id changes.
@Observable
final class WBMacOSWhiteboardImageViewModel {
    private let imageProvider: WBMacOSWhiteboardImageProviding
    private var loadedImageID: String?
    private var hasStartedLoading = false

    private(set) var image: NSImage?

    /// True once a fetch for the current id resolved to no image — drives the static
    /// "no photo" placeholder instead of an endless loading spinner.
    private(set) var isImageUnavailable = false

    init(imageProvider: WBMacOSWhiteboardImageProviding) {
        self.imageProvider = imageProvider
    }

    /// Loads the image for `imageID`, replacing whatever was shown when the id changed.
    /// A failed or unresolvable fetch marks the image unavailable rather than erroring.
    func loadImage(forImageID imageID: String?) async {
        guard !hasStartedLoading || imageID != loadedImageID else {
            return
        }
        hasStartedLoading = true
        loadedImageID = imageID
        image = nil
        isImageUnavailable = false
        guard let imageID else {
            isImageUnavailable = true
            return
        }
        let loadedImage = try? await imageProvider.image(forImageID: imageID)
        guard !Task.isCancelled else {
            return
        }
        // A stale completion (the id changed again mid-flight) must not clobber the newer load.
        guard loadedImageID == imageID else {
            return
        }
        image = loadedImage
        isImageUnavailable = loadedImage == nil
    }
}
