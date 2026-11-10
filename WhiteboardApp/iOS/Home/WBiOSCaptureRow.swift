import SwiftUI
import UIKit

/// A single "Recent Captures" row: the photo on the left, then the capture title and its timestamp.
/// The photo loads lazily (a spinner shows while it downloads); `loadImage` is supplied by the
/// screen and resolves the `imageID` to an image (or `nil` when unavailable).
struct WBiOSCaptureRow: View {
    let capture: WBiOSCapture
    let loadImage: (String) async -> UIImage?

    private let thumbnailSize: CGFloat = 60

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        HStack(spacing: .spacingMD) {
            thumbnail
            VStack(alignment: .leading, spacing: .spacingXXS) {
                Text(capture.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(capture.timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var thumbnail: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .radiusSM))
        .task(id: capture.id) {
            isLoading = true
            image = await loadImage(capture.imageID)
            isLoading = false
        }
    }
}
