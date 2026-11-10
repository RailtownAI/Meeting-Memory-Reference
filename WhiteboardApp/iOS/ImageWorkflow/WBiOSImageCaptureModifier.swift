import PhotosUI
import SwiftUI

/// Attaches the shared image-capture flow — source dialog → camera / photo picker → permission alert
/// — driven by a `WBiOSImageCaptureModel`. Call `model.start()` to begin; each captured image is
/// delivered to `onImage`.
private struct WBiOSImageCaptureModifier: ViewModifier {
    @Bindable var model: WBiOSImageCaptureModel
    let onImage: (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Capture Whiteboard",
                isPresented: $model.isSourceDialogPresented,
                titleVisibility: .hidden
            ) {
                if model.isCameraAvailable {
                    Button("Camera") {
                        model.chooseCamera()
                    }
                }
                Button("Photo Album") {
                    model.choosePhotoAlbum()
                }
            }
            .fullScreenCover(isPresented: $model.isCameraPresented) {
                WBiOSCameraPicker { image in
                    onImage(model.cameraImage(image))
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $model.isPhotoPickerPresented,
                selection: $model.photoPickerItem,
                matching: .images
            )
            .onChange(of: model.photoPickerItem) {
                Task {
                    if let image = await model.loadPickedPhoto() {
                        onImage(image)
                    }
                }
            }
            .alert("Camera Access Needed", isPresented: $model.isPermissionAlertPresented) {
                Button("Cancel", role: .cancel) {
                }
                Button("Settings") {
                    model.openSettings()
                }
            } message: {
                Text("Enable camera access in Settings to capture whiteboard photos.")
            }
    }
}

extension View {
    /// Adds the shared image-capture flow driven by `model`; captured images are delivered to
    /// `onImage`. Trigger it with `model.start()`.
    func imageCapture(
        _ model: WBiOSImageCaptureModel,
        onImage: @escaping (UIImage) -> Void
    ) -> some View {
        modifier(WBiOSImageCaptureModifier(model: model, onImage: onImage))
    }
}
