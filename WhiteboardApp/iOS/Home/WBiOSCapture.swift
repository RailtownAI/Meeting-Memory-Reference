import Foundation
import WhiteboardCore

/// iOS-side display model for a whiteboard capture row in the Home screen's "Recent Captures"
/// section — a slimmed mapping of Core's `WBWhiteboardRecord` holding only what a row shows plus
/// the `imageID` used to lazily fetch the photo.
struct WBiOSCapture: Identifiable {
    let id: String
    /// iCloud photo reference, resolved lazily per row.
    let imageID: String
    /// Row line 1 — the capture's title (`WBWhiteboardRecord.title`).
    let title: String
    /// Row line 2 — when the photo was captured, preformatted.
    let timestampText: String

    /// Maps a Core `WBWhiteboardRecord` to the row model. `formatter` is injected (VM-owned) so it
    /// isn't rebuilt per row.
    init(from record: WBWhiteboardRecord, formatter: DateFormatter) {
        self.id = record.id
        self.imageID = record.imageId
        self.title = record.title
        if record.capturedAtEpoch > 0 {
            let captured = Date(timeIntervalSince1970: TimeInterval(record.capturedAtEpoch))
            self.timestampText = formatter.string(from: captured)
        } else {
            self.timestampText = "Unknown time"
        }
    }
}
