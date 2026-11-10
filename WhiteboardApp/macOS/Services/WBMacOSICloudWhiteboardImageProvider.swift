import AppKit
import WhiteboardCore

/// Provides the photo for a whiteboard's `imageID`.
///
/// Returns `nil` when the asset cannot be resolved — callers keep their placeholder.
protocol WBMacOSWhiteboardImageProviding {
    func image(forImageID imageID: String) async throws -> NSImage?
}

/// Real image provider: resolves a whiteboard's `imageID` to its photo in the shared iCloud
/// container (`WBFileStore`), decoding into an `NSImage`.
///
/// Decoded images are cached (shared across instances — the provider is a value type that's
/// recreated freely) so carousel paging and thumbnail reuse don't re-read iCloud.
struct WBMacOSICloudWhiteboardImageProvider: WBMacOSWhiteboardImageProviding {
    private static let imageCache = NSCache<NSString, NSImage>()

    func image(forImageID imageID: String) async throws -> NSImage? {
        if let cachedImage = WBMacOSICloudWhiteboardImageProvider.imageCache.object(
            forKey: imageID as NSString
        ) {
            return cachedImage
        }
        guard let data = try await WBFileStore.photoData(forImageID: imageID) else {
            return nil
        }
        guard let image = NSImage(data: data) else {
            return nil
        }
        WBMacOSICloudWhiteboardImageProvider.imageCache.setObject(image, forKey: imageID as NSString)
        return image
    }
}
