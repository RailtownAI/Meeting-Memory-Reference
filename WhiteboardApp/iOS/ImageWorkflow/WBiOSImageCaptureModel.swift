import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import WhiteboardCore

/// Reusable image-capture flow shared by any screen that needs a photo from the camera or the photo
/// library — Home's initial capture and the review screen's "Retake". Owns the source-selection,
/// camera, photo-picker, and permission state; the captured `UIImage` is delivered through the
/// `imageCapture(_:onImage:)` view modifier.
@Observable
@MainActor
final class WBiOSImageCaptureModel {
    var isSourceDialogPresented = false
    var isCameraPresented = false
    var isPhotoPickerPresented = false
    var isPermissionAlertPresented = false
    var photoPickerItem: PhotosPickerItem?

    /// Whether this device has a camera (false on the Simulator) — gates the Camera option.
    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Begins capture by presenting the source action sheet.
    func start() {
        isSourceDialogPresented = true
    }

    /// The user chose "Camera". Presents the camera, or the settings alert if access was denied.
    func chooseCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized, .notDetermined:
            isCameraPresented = true
        case .denied, .restricted:
            WBLog.warning("⚠️📷 Camera access unavailable (denied/restricted)")
            isPermissionAlertPresented = true
        @unknown default:
            isPermissionAlertPresented = true
        }
    }

    /// The user chose "Photo Album".
    func choosePhotoAlbum() {
        isPhotoPickerPresented = true
    }

    /// Logs a camera capture and returns it unchanged (keeps logging in the Core-aware model).
    func cameraImage(_ image: UIImage) -> UIImage {
        WBLog.debug("📷 Captured image from camera (\(Int(image.size.width))×\(Int(image.size.height)))")
        return image
    }

    /// Loads the selected photo-picker item's image, clears the selection, and returns it
    /// (`nil` on failure).
    func loadPickedPhoto() async -> UIImage? {
        guard let photoPickerItem else {
            return nil
        }
        defer { self.photoPickerItem = nil }
        if let data = try? await photoPickerItem.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            WBLog.debug("📷 Loaded picked photo (\(Int(image.size.width))×\(Int(image.size.height)))")
            return image
        }
        WBLog.warning("⚠️📷 Failed to load the selected photo")
        return nil
    }

    /// Opens the app's Settings page so the user can grant camera access.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
