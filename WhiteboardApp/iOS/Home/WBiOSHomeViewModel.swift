import Observation
import UIKit

/// Home screen state. The capture flow itself lives in the reusable `WBiOSImageCaptureModel`; this
/// only holds the image currently awaiting review.
@Observable
@MainActor
final class WBiOSHomeViewModel {
    /// The image awaiting review. Non-nil presents `WBiOSImageReviewView` from Home; cleared when
    /// the user cancels or saves. Held only for the review hand-off — after Save the image lives in
    /// iCloud + railengine and reappears as a "Recent Captures" row, so it isn't retained here.
    var capturedImage: UIImage?
}
