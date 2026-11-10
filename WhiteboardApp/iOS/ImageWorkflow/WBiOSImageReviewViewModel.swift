import Observation
import UIKit
import WhiteboardCore

/// View model for `WBiOSImageReviewView` — holds the captured image under review, the two analysis
/// runs it feeds (LLM title/summary and on-device OCR), and the meeting it will be linked to.
///
/// Saving itself belongs to `WBiOSSaveResultViewModel`: this screen hands the generated text to the
/// result screen, which runs the upload → ingest pipeline.
@Observable
@MainActor
final class WBiOSImageReviewViewModel {
    /// One row of the Action Items section. Nested — doesn't repeat the type prefix, per the coding
    /// style. Identity is a `UUID` rather than the row's position: rows are deletable, and position
    /// identity would hand a removed row's view state (its swipe offset) to whichever item shifted
    /// up into its index.
    struct ActionItem: Identifiable, Hashable {
        let id = UUID()
        var text: String
        /// True when the row's wording is the user's — typed from scratch, or a generated row they
        /// went on to edit. Generated rows are replaced by each analysis run; these survive one, and
        /// are the only ones whose loss warrants a retake confirmation. Editing flips it, so a
        /// reworded row can't be quietly reverted by a re-run or discarded by an unwarned retake.
        var isManual: Bool
    }

    /// A failed generation run, kept so the screen can say what went wrong and offer another go.
    /// Nested — doesn't repeat the type prefix, per the coding style.
    ///
    /// Two strings rather than the `Error` itself: the view renders what it's handed, and mapping an
    /// error to wording is logic that belongs on this side of the boundary.
    struct AnalysisFailure {
        /// The line under the title. Deliberately the same sentence for every failure: what the
        /// user can do about it doesn't change with the cause, and the cause is on the line below.
        let message: String

        /// Where the failure came from, in the failing layer's own terms. Shown only in DEBUG
        /// builds — see `alertText`.
        let detail: String

        /// Wording for any failed run. A `LocalizedError` further down may have written something
        /// more specific, but this screen offers one remedy, so it says that one thing plainly and
        /// leaves the specifics to `detail`.
        static let generalMessage = "Unable to analyze photo. Please try uploading again."

        init(message: String, detail: String) {
            self.message = message
            self.detail = detail
        }

        init(error: any Error) {
            message = Self.generalMessage
            detail = Self.truncated(String(reflecting: error))
        }

        /// What the pop-up shows.
        ///
        /// Release builds show the message alone: the point of a general sentence is that the user
        /// doesn't have to read "models/not-a-real-model is not found for API version v1beta" to
        /// know what to do next. Debug builds append it, because whoever is running the app then is
        /// exactly the person who needs to know which layer failed and why. `WBLog.error` records
        /// it either way, so nothing is lost in release — it's just not on screen.
        var alertText: String {
            #if DEBUG
            return "\(message)\n\n\(detail)"
            #else
            return message
            #endif
        }

        /// An alert can't scroll, and a provider's error body runs long enough to push the buttons
        /// off screen — so the tail is dropped rather than the whole thing being unreadable.
        private static func truncated(_ text: String, limit: Int = 300) -> String {
            guard text.count > limit else {
                return text
            }
            return text.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
    }

    /// The image under review. Swap it only through `setImage(_:)` — that's where the action items
    /// are cleared, so assigning here directly would carry the previous board's typed items onto a
    /// different photo.
    private(set) var image: UIImage

    /// Meetings the capture can be assigned to — the selection list shown during review.
    let meetings: [WBiOSMeeting]

    /// `WBiOSMeeting.id` of the currently chosen meeting (defaults to the one selected on Home — a
    /// meeting is always selected at capture time, since the capture button is gated on it). Mutable
    /// so the review screen can reassign the capture to a different meeting.
    var selectedMeetingID: String

    /// Whether the LLM is still generating the title / summary — drives the header spinners. Cleared
    /// when the run started by `analyze()` completes (or fails).
    var isTitleLoading = true
    var isSummaryLoading = true

    /// Whether Vision is still reading the text off the photo — drives the OCR header spinner.
    var isOCRLoading = true

    /// Whether the review screen shows the OCR section. Off for now — recognition still **runs**
    /// and its text is still ingested into `WBWhiteboardRecord.ocrText`; this hides the display
    /// only. Flip to `true` to read the transcript while comparing `WBOCRService.mode`, which is
    /// the quickest way to see what a route actually produced.
    let isOCRSectionVisible = false

    /// LLM-generated section text; empty until generation completes.
    var title = ""
    var summary = ""

    /// Every action item, in display and ingestion order. A run's generated items go in at the
    /// front and typed ones are appended, so the list starts out generated-then-manual — but that
    /// grouping isn't an invariant: editing a generated row marks it manual where it stands.
    ///
    /// One array rather than a generated/manual pair, now that rows are deletable: a deleted row has
    /// to resolve to a single home by `id`, and display order stops being derivable from
    /// concatenation once rows can disappear. `ActionItem.isManual` carries the distinctions the
    /// split was protecting.
    private(set) var actionItems: [ActionItem] = []

    /// The item text, in order — what the save path ingests.
    var actionItemTexts: [String] {
        actionItems.map(\.text)
    }

    /// Whether retaking would destroy something the user can't get back. Generated items don't
    /// count: a retake regenerates them from the new photo.
    var shouldConfirmRetake: Bool {
        actionItems.contains(where: \.isManual)
    }

    /// Text recognized on the whiteboard, pre-joined into the single string the OCR section renders
    /// and `ocrText` ingests. Legitimately empty for a photo with no legible text.
    var ocrText = ""

    /// Whether OCR failed, as distinct from succeeding with nothing to show — for a photo of a
    /// diagram, an empty `ocrText` is the correct answer rather than an error. Reset when a run
    /// starts, so a retake clears the previous failure.
    private(set) var didOCRFail = false

    /// Whether a generated section finished with nothing in it — either the LLM call failed or it
    /// returned an empty string for that field. Both mean "nothing to show, and that's wrong", so
    /// the section shows its error line. Unlike OCR there's no legitimate empty result here, which
    /// is why these are derived rather than tracked. Gated on the loading flag, so neither can be
    /// true before a run starts or while one is in flight.
    /// Whether the run that produces the action items is still going. They arrive from the same
    /// summarize call as the title and summary, so this tracks that call rather than a flag of its
    /// own — it disables "Add Action Item" until the generated items have landed, since a result
    /// assigns `actionItems` wholesale and would discard anything added in the meantime.
    var isActionItemsLoading: Bool { isTitleLoading || isSummaryLoading }

    var didTitleFail: Bool { !isTitleLoading && title.isEmpty }
    var didSummaryFail: Bool { !isSummaryLoading && summary.isEmpty }

    /// Why the last generation run failed, or `nil` when it succeeded. Outlives the pop-up on
    /// purpose: dismissing the alert leaves the inline retry on screen, so the user who taps away
    /// isn't left with a dead end.
    private(set) var summarizeFailure: AnalysisFailure?

    /// Whether the failure pop-up is on screen. Mutable so the view can bind it and SwiftUI can
    /// clear it on dismissal, matching `WBiOSSettingsViewModel.isConfirmingDelete`. Set only
    /// alongside `summarizeFailure`, so the two can't disagree about whether a run failed.
    var isSummarizeFailureAlertPresented = false

    /// Whether the review can be saved. Title and summary must have generated text — this is false
    /// while generating (the text is cleared then) and on failure (it stays empty).
    ///
    /// OCR only gates the save while its section is on screen, and then only until it *finishes*:
    /// a diagram-only whiteboard yields no text and must still be saveable. With the section hidden
    /// there's nothing on screen to explain the wait, so `isOCRLoading` is ignored entirely.
    var canSave: Bool {
        !title.isEmpty && !summary.isEmpty && !(isOCRSectionVisible && isOCRLoading)
    }

    private let summarizer = WBImageSummarizeService()
    private let ocrService = WBOCRService()
    private var summarizeTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?

    init(image: UIImage, meetings: [WBiOSMeeting], selectedMeetingID: String) {
        self.image = image
        self.meetings = meetings
        self.selectedMeetingID = selectedMeetingID
    }

    /// The currently chosen meeting, resolved from `selectedMeetingID`.
    var selectedMeeting: WBiOSMeeting? {
        meetings.first { $0.id == selectedMeetingID }
    }

    /// Runs (or re-runs) both analyses for the current image. A new run supersedes any in-flight
    /// one; call on appear and after a retake.
    ///
    /// The two runs share **one** JPEG encode. Encoding a full-resolution photo costs roughly
    /// 100–200ms on the main actor, so doing it once per analysis rather than once per run keeps
    /// that off the frame budget twice over. They then proceed concurrently: recognition is
    /// on-device and lands well before the LLM call.
    func analyze() {
        let data = encodedImageData()
        summarize(imageData: data)
        recognizeText(imageData: data)
    }

    /// Re-runs the title / summary / action-item generation after a failure — what the pop-up's
    /// Retry and the inline retry both call.
    ///
    /// Only that half re-runs. Recognition is on-device, has already finished by the time an LLM
    /// call fails, and its text is what the save ingests — re-running it would throw away a good
    /// transcript to retry the half that didn't fail. Re-encoding is the cost of not holding a
    /// second copy of a full-resolution photo for the screen's lifetime.
    func retrySummarize() {
        summarize(imageData: encodedImageData())
    }

    /// The photo as JPEG bytes, or `nil` when it can't be encoded.
    ///
    /// Encodes on the main actor so the (Sendable) `Data` — not the UIImage — crosses into the
    /// tasks. Shared by `analyze()` and `retrySummarize()`: both need the same bytes, and the
    /// warning below should read the same either way.
    private func encodedImageData() -> Data? {
        let data = image.jpegData(compressionQuality: 0.9)
        if data == nil {
            WBLog.warning("⚠️🖼️ Could not encode image for analysis")
        }
        return data
    }

    /// Cancels both in-flight analyses. Called when the user leaves the review without saving, so a
    /// discarded capture stops paying for the LLM call and Vision recognition.
    func cancelAnalysis() {
        summarizeTask?.cancel()
        ocrTask?.cancel()
    }

    /// Appends an action item the user typed. Blank input is ignored — the prompt's OK button is
    /// disabled for it, and this is the backstop.
    func addActionItem(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        actionItems.append(ActionItem(text: trimmed, isManual: true))
        // Read the count into a local first: `WBLog`'s message is a `@Sendable` autoclosure, which
        // can't reference main-actor state directly.
        let count = actionItems.count
        WBLog.debug("➕ Added action item by hand — \(count) item(s) total")
    }

    /// Removes an action item. Applies to generated and manual rows alike — the likelier need is
    /// dropping something the model got wrong. There's no undo: a manual item can be retyped, but a
    /// deleted generated one only returns via a retake, which discards everything else too.
    ///
    /// A deleted generated item stays gone for this photo; nothing re-runs generation except retake.
    func deleteActionItem(id: ActionItem.ID) {
        actionItems.removeAll { $0.id == id }
        let remaining = actionItems.count
        WBLog.debug("🗑️ Deleted action item — \(remaining) item(s) remaining")
    }

    /// Replaces an item's text with the user's wording, and marks the row as theirs.
    ///
    /// Blank input leaves the row untouched, matching `addActionItem` — emptying the field isn't a
    /// back door to deleting a row, which is what the swipe action is for. Marking it manual is what
    /// stops a reworded generated row being silently replaced by the model on the next same-photo
    /// run, or discarded by a retake that never warned about it.
    func updateActionItem(id: ActionItem.ID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let index = actionItems.firstIndex(where: { $0.id == id }) {
            actionItems[index].text = trimmed
            actionItems[index].isManual = true
            WBLog.debug("✏️ Edited action item")
        }
    }

    /// Replaces the reviewed image (retake) and re-runs both analyses. Manually-added items go too:
    /// they were written against the board being replaced, and the user has already confirmed losing
    /// them (see `shouldConfirmRetake`).
    func setImage(_ image: UIImage) {
        self.image = image
        actionItems.removeAll()
        analyze()
    }

    /// Generates the title, summary, and action items. `imageData` is `nil` when the photo couldn't
    /// be encoded, which is handled as a failed run.
    private func summarize(imageData: Data?) {
        summarizeTask?.cancel()
        isTitleLoading = true
        isSummaryLoading = true
        // Clear stale results so a previous run's don't linger beside the spinner (e.g. after retake).
        title = ""
        summary = ""
        summarizeFailure = nil
        isSummarizeFailureAlertPresented = false
        // Clears the generated items only — anything the user typed or edited stays.
        //
        // This can run a second time for the *same* photo, because the review screen's `.task`
        // re-fires if the view disappears and comes back: popping back from the result screen is the
        // reachable route, and whether dismissing a presented cover also counts has varied by iOS
        // version. `image` is untouched on any of those, so the user's wording still describes the
        // board on screen and has to survive — clearing the whole list would destroy their work over
        // a navigation they never meant as "start over". A genuinely new photo arrives through
        // `setImage`, which empties everything after confirming with the user.
        actionItems.removeAll { !$0.isManual }

        summarizeTask = Task { [weak self] in
            guard let self else { return }
            var result: WBImageSummary?
            var failure: AnalysisFailure?
            if let imageData {
                do {
                    result = try await summarizer.summarize(imageData: imageData)
                } catch {
                    let description = "\(error)"
                    WBLog.error("⚠️🖼️ Summarize failed: \(description)")
                    failure = AnalysisFailure(error: error)
                }
            } else {
                // A photo that wouldn't encode never reached the model — same remedy, different
                // cause, so only the detail line differs from a failed call.
                failure = AnalysisFailure(
                    message: AnalysisFailure.generalMessage,
                    detail: "The captured image could not be encoded as JPEG."
                )
            }
            guard !Task.isCancelled else {
                return  // superseded by a newer run — leave its state alone
            }
            if let result {
                title = result.title
                summary = result.summary
                // Inserted ahead of any manual items, keeping generated-then-manual order without
                // having to sort.
                actionItems.insert(
                    contentsOf: result.actionItems.map { ActionItem(text: $0, isManual: false) },
                    at: 0
                )
            }
            // A failure leaves both empty, which `didTitleFail` / `didSummaryFail` surface as the
            // sections' error lines once loading clears. The pop-up is the loud half of the same
            // news: it names the cause, which an empty section can't.
            summarizeFailure = failure
            isSummarizeFailureAlertPresented = failure != nil
            isTitleLoading = false
            isSummaryLoading = false
        }
    }

    /// Reads the text off the photo. `imageData` is `nil` when the photo couldn't be encoded, which
    /// is handled as a failed run.
    private func recognizeText(imageData: Data?) {
        ocrTask?.cancel()
        isOCRLoading = true
        didOCRFail = false
        // Clear stale text so a previous photo's transcript doesn't linger after a retake.
        ocrText = ""

        ocrTask = Task { [weak self] in
            guard let self else { return }
            var result: String?
            if let imageData {
                do {
                    result = try await ocrService.recognizeText(imageData: imageData)
                } catch {
                    let description = "\(error)"
                    WBLog.error("⚠️👁️ OCR failed: \(description)")
                }
            }
            guard !Task.isCancelled else {
                return  // superseded by a newer run — leave its state alone
            }
            if let result {
                ocrText = result
            } else {
                didOCRFail = true
            }
            // A failure leaves the text empty rather than blocking the save; the record just
            // ingests an empty `ocrText`.
            isOCRLoading = false
        }
    }
}
