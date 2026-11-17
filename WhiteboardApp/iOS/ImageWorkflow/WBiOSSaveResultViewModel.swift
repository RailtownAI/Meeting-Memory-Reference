import Observation
import UIKit
import WhiteboardCore

/// Runs the whiteboard save pipeline (upload → ingest) and exposes its result for the result screen.
/// The screen performs the save on appear and on Retry.
@Observable
@MainActor
final class WBiOSSaveResultViewModel {
    enum State {
        case loading
        case saved
        case failed
    }

    let image: UIImage
    let title: String
    let summary: String
    /// Pre-joined OCR transcript from the review screen. Empty when the photo held no legible text.
    let ocrText: String

    /// Action items minted from the review screen's plain strings — this screen is the boundary where
    /// they become contract records. Built **once** in `init`, like `ids`, so a retry re-ingests the
    /// same items instead of minting fresh ids on every attempt.
    let actionItems: [WBActionItem]

    let meeting: WBiOSMeeting

    private(set) var state: State = .loading
    private let saveService = WBWhiteboardSaveService()
    private let recordStore = WBWhiteboardRecordStore()

    /// Whether to run the post-save affirmation queries (extra railengine calls + logs). Gated so a
    /// release build never pays the cost; DEBUG builds opt in by default. Flip to force it in a build.
    #if DEBUG
    private let runSaveDiagnostics = true
    #else
    private let runSaveDiagnostics = false
    #endif

    /// Capture identity, minted once so a retry after a failed ingest reuses the same ids and skips
    /// re-uploading the photo to iCloud. A new capture gets a new view model → new ids → new record.
    private let ids = WBWhiteboardSaveService.makeIDs()

    init(
        image: UIImage,
        title: String,
        summary: String,
        ocrText: String,
        actionItemTexts: [String],
        meeting: WBiOSMeeting
    ) {
        self.image = image
        self.title = title
        self.summary = summary
        self.ocrText = ocrText
        self.actionItems = WBActionItem.make(from: actionItemTexts)
        self.meeting = meeting
    }

    /// Performs the save. Called on appear and on Retry.
    func save() async {
        state = .loading
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            WBLog.error("⚠️💾 Could not encode image for save")
            state = .failed
            return
        }
        let meetingID = meeting.meetingID
            ?? WBMeetingID.mint(
                eventUID: meeting.calendarItemExternalIdentifier,
                startEpoch: meeting.startEpoch
            )
        do {
            let record = try await saveService.save(
                imageData: data,
                id: ids.id,
                imageID: ids.imageID,
                title: title,
                summary: summary,
                ocrText: ocrText,
                actionItems: actionItems,
                meetingID: meetingID,
                eventUID: meeting.calendarItemExternalIdentifier,
                occurrenceStart: meeting.start,
                capturedByDevice: UIDevice.current.name
            )
            state = .saved

            // Spotlight (and Siri, through it) learns about the whiteboard from the record just
            // ingested, not a read-back: ingest is queued, so a fetch now could miss it.
            let meetingTitle = meeting.title
            Task {
                await WBWhiteboardSpotlight.index(record, meetingTitle: meetingTitle)
            }

            if runSaveDiagnostics {
                // Affirmation: after a successful ingest, re-query the whiteboard engine three ways —
                // by `id`, by `meetingId` (Home's path), and by `imageId` — once immediately and once
                // after 15s, to confirm the record landed and is queryable (and spot index lag).
                let store = recordStore
                let captureIDs = ids
                Task {
                    await Self.logDiagnosticQueries(
                        store: store, meetingID: meetingID, id: captureIDs.id, imageID: captureIDs.imageID, label: "immediate"
                    )
                    try? await Task.sleep(for: .seconds(15))
                    await Self.logDiagnosticQueries(
                        store: store, meetingID: meetingID, id: captureIDs.id, imageID: captureIDs.imageID, label: "after 15s"
                    )
                }
            }
        } catch {
            let description = "\(error)"
            WBLog.error("⚠️💾 Whiteboard save failed: \(description)")
            state = .failed
        }
    }

    /// Affirmation: counts the just-saved record in the whiteboard engine three ways (by id /
    /// meetingId / imageId), to confirm the ingest landed and is queryable. `nonisolated` + all-
    /// `Sendable` args so it runs off-main and outlives the view model (the delayed pass still logs
    /// after the result screen is dismissed). A count of `error` means that query threw.
    nonisolated private static func logDiagnosticQueries(
        store: WBWhiteboardRecordStore,
        meetingID: String,
        id: String,
        imageID: String,
        label: String
    ) async {
        let byID = (try? await store.records(ids: [id]))?.count
        let byMeeting = (try? await store.records(meetingID: meetingID))?.count
        let byImage = (try? await store.records(imageID: imageID))?.count
        let idText = byID.map(String.init) ?? "error"
        let meetingText = byMeeting.map(String.init) ?? "error"
        let imageText = byImage.map(String.init) ?? "error"
        WBLog.info(
            "🔁🖼️ [\(label)] whiteboard fetch — by id: \(idText), by meetingID: \(meetingText), by imageID: \(imageText)"
        )
    }
}
