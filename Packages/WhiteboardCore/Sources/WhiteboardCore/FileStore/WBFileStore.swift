import Foundation

/// Photo store on the app's iCloud Drive (ubiquity) container — the photo binary never leaves
/// the user's iCloud; railengine records only carry the app-minted `imageID` reference. Keeping
/// the image out of the vector database is the core privacy guarantee: a whiteboard photo can
/// hold anything, so only text derived from it is ever ingested.
///
/// Photos are plain files at `Documents/Photos/<imageID>`, synced by iCloud Drive — deliberately
/// the simple file-based mechanism, chosen over CloudKit/`CKAsset`: once a file materializes
/// locally, reads are local for free. The API exposes only bytes-by-id, so a CloudKit-backed store
/// could swap in behind it later.
public enum WBFileStore {
    public enum WBFileStoreError: LocalizedError {
        case iCloudUnavailable
        /// The photo exists in iCloud but didn't finish downloading in time.
        case downloadTimedOut(imageID: String)

        public var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud is unavailable — sign in to iCloud and enable the iCloud capability."
            case .downloadTimedOut(let imageID):
                return "Downloading the photo for \(imageID) from iCloud timed out. Try again."
            }
        }
    }

    /// How long `photoData(forImageID:)` waits for iCloud to materialize a file.
    private static let photoDownloadTimeout = Duration.seconds(30)

    /// Delay between checks while waiting for a file to materialize.
    private static let photoDownloadPollInterval = Duration.milliseconds(300)

    /// Whether iCloud is currently available to the app.
    public static var isICloudAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    /// Uploads a photo, replacing any photo already stored under the same id.
    public static func uploadPhotoData(_ data: Data, imageID: String) throws {
        let destination = try photoURL(forImageID: imageID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        // setUbiquitous MOVES its source into iCloud, so stage the bytes in a temp file.
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: temporaryURL)
        try FileManager.default.setUbiquitous(
            true,
            itemAt: temporaryURL,
            destinationURL: destination
        )
    }

    /// The photo data stored under `imageID`, or `nil` when no photo exists for it (or its
    /// iCloud metadata hasn't reached this device yet). A known-but-undownloaded photo is
    /// materialized on demand before being read.
    public static func photoData(forImageID imageID: String) async throws -> Data? {
        let url = try photoURL(forImageID: imageID)
        let placeholderURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(imageID).icloud")

        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.fileExists(atPath: placeholderURL.path) else {
                return nil
            }
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            var waited = Duration.zero
            while !FileManager.default.fileExists(atPath: url.path) {
                guard waited < photoDownloadTimeout else {
                    throw WBFileStoreError.downloadTimedOut(imageID: imageID)
                }
                try await Task.sleep(for: photoDownloadPollInterval)
                waited += photoDownloadPollInterval
            }
        }

        var coordinatorError: NSError?
        var data: Data?
        var readError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { readableURL in
            do {
                data = try Data(contentsOf: readableURL)
            } catch {
                readError = error
            }
        }
        if let coordinatorError {
            throw coordinatorError
        }
        if let readError {
            throw readError
        }
        return data
    }

    /// Whether a photo is stored under `imageID` — true even when its bytes haven't downloaded to
    /// this device yet (an iCloud placeholder counts). Cheaper than `listPhotoIDs()` membership.
    public static func photoExists(imageID: String) throws -> Bool {
        let url = try photoURL(forImageID: imageID)
        let placeholderURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(imageID).icloud")
        return FileManager.default.fileExists(atPath: url.path)
            || FileManager.default.fileExists(atPath: placeholderURL.path)
    }

    /// Deletes every stored photo, returning the number removed. Removes the whole Photos folder
    /// (recreated lazily on the next upload); iCloud only — no other app data is touched. The removal
    /// is file-coordinated (`.forDeleting`) so it doesn't race the iCloud sync daemon.
    @discardableResult
    public static func deleteAllPhotos() throws -> Int {
        let count = try listPhotoIDs().count
        let directory = try photosDirectoryURL()

        var coordinatorError: NSError?
        var removeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: directory,
            options: .forDeleting,
            error: &coordinatorError
        ) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                removeError = error
            }
        }
        if let coordinatorError {
            throw coordinatorError
        }
        if let removeError {
            throw removeError
        }
        return count
    }

    /// The `imageID`s of every photo currently in the container's Photos folder, sorted —
    /// including photos whose bytes haven't downloaded to this device yet.
    public static func listPhotoIDs() throws -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: photosDirectoryURL(),
            includingPropertiesForKeys: nil
        )
        return (contents ?? [])
            .map { normalizePlaceholder($0) }
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }
}

private extension WBFileStore {
    /// The container's `Documents/Photos` folder, creating it on first use. Throws when iCloud
    /// is unavailable.
    private static func photosDirectoryURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw WBFileStoreError.iCloudUnavailable
        }
        let photosURL = container
            .appendingPathComponent("Documents")
            .appendingPathComponent("Photos")
        try FileManager.default.createDirectory(
            at: photosURL,
            withIntermediateDirectories: true
        )
        return photosURL
    }

    /// The photo's URL in the container's Photos folder.
    private static func photoURL(forImageID imageID: String) throws -> URL {
        try photosDirectoryURL().appendingPathComponent(imageID)
    }

    /// Converts an on-disk iCloud placeholder URL (`/dir/.name.ext.icloud`) to the item's real URL
    /// (`/dir/name.ext`). Non-placeholder URLs are returned unchanged.
    private static func normalizePlaceholder(_ url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else {
            return url
        }
        let withoutLeadingDot = String(name.dropFirst())
        let realName = String(withoutLeadingDot.dropLast(".icloud".count))
        return url.deletingLastPathComponent().appendingPathComponent(realName)
    }
}
