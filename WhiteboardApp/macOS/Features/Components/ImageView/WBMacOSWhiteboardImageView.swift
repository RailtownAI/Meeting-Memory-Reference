import SwiftUI

/// The single place a whiteboard photo turns into pixels: renders its view model's image,
/// with a loading placeholder while a fetch is in flight and a "no photo" placeholder once
/// the id resolves to nothing. Reloads itself whenever `imageID` changes.
struct WBMacOSWhiteboardImageView: View {
    let imageID: String?
    let cornerRadius: CGFloat

    @State private var viewModel: WBMacOSWhiteboardImageViewModel

    init(
        imageID: String?,
        cornerRadius: CGFloat,
        imageProvider: WBMacOSWhiteboardImageProviding
    ) {
        self.imageID = imageID
        self.cornerRadius = cornerRadius
        _viewModel = State(
            initialValue: WBMacOSWhiteboardImageViewModel(imageProvider: imageProvider)
        )
    }

    var body: some View {
        Group {
            if let image = viewModel.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(.quinary)
                    .overlay {
                        if viewModel.isImageUnavailable {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: imageID) {
            await viewModel.loadImage(forImageID: imageID)
        }
    }
}
