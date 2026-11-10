import CoreGraphics
import Foundation

/// One piece of text Vision recognized, with where it sits on the board.
///
/// Vision returns these in no particular order — reading order has to be reconstructed from the
/// geometry, which is what the coordinates are for.
public struct WBOCRSegment: Sendable, Hashable {
    public let text: String

    /// Normalized bounding box in **Vision's** space: `0...1` on both axes with the origin at the
    /// **lower left**, so a larger `y` is higher up the photo.
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public extension WBOCRSegment {
    /// The box with the origin flipped to the **top left** and `y` growing downward — how people
    /// (and models) read a page, and the form the reconstruction prompt uses.
    var topLeftBoundingBox: CGRect {
        CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.maxY,
            width: boundingBox.width,
            height: boundingBox.height
        )
    }
}
