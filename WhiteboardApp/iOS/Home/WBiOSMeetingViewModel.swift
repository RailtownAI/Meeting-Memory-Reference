import Observation
import UIKit
import WhiteboardCore

/// Loads the most recent already-started meeting from the calendar for the Home screen.
///
/// Keeps the full candidate list in memory (latest first) to support a future "swap meeting" action
/// when the auto-selected one isn't the intended one.
@Observable
@MainActor
final class WBiOSMeetingViewModel {
    enum State {
        case loading
        case loaded(WBiOSMeeting)
        case empty
        case accessDenied
    }

    /// State of the "Recent Captures" section for the displayed meeting.
    enum CapturesState {
        case loading
        case loaded([WBiOSCapture])
        case iCloudUnavailable
    }

    private(set) var state: State = .loading

    /// Captures for the displayed meeting. `.loaded([])` when there are none (or before any meeting).
    private(set) var capturesState: CapturesState = .loaded([])

    /// All candidate meetings (latest start first). Kept for a future manual meeting swap.
    private(set) var meetings: [WBiOSMeeting] = []

    private let eventService = WBEventKitService()
    private let syncService = WBiOSMeetingSyncService()
    private let contentLoader = WBMeetingContentLoader()

    /// Off-main task resolving the selected meeting's railengine link id. Cancelled on swap.
    private var enrichTask: Task<Void, Never>?

    /// How far back to search for the latest meeting.
    private let searchWindowDays = 7

    /// Look-ahead grace: also count meetings that start within this window from now, so a meeting
    /// about to start still surfaces on Home.
    private let searchLookAhead: TimeInterval = 15 * 60

    /// `id` of the meeting currently on display. Preserved across refresh: if it still exists in
    /// the refreshed list, that meeting stays selected; otherwise the latest is shown.
    private(set) var selectedID: String?

    /// Shared formatters owned here so each `WBiOSMeeting` doesn't allocate its own on every render.
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private let captureTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy 'at' h:mma"
        return formatter
    }()

    /// Loads the latest meeting. Requests calendar access if undetermined; sets `.accessDenied`
    /// when access isn't granted. Call on appear and on pull-to-refresh.
    ///
    /// `force` re-runs the per-meeting background work even when the displayed meeting is unchanged
    /// — used by pull-to-refresh so the user can retry a failed sync. Normal appear/selection leaves
    /// it `false` to avoid redundant work.
    func load(source: String, force: Bool = false) async {
        let cachedCount = meetings.count
        WBLog.info("🔄🏠 load[\(source)] start — cached meetings: \(cachedCount)")
        state = .loading

        // `requestFullAccess` prompts only when access is undetermined; otherwise it returns the
        // existing grant without re-prompting — so calling it unconditionally is safe on refresh.
        let couldPrompt = eventService.canRequestAccess
        let hasAccess = (try? await eventService.requestFullAccess()) ?? false
        WBLog.info("🔄🏠 load[\(source)] hasAccess=\(hasAccess)")
        guard hasAccess else {
            state = .accessDenied
            return
        }
        if couldPrompt {
            // Just granted: Siri can now learn the meeting names for the Remember phrases.
            WBiOSShortcutVocabulary.refresh(reason: "calendar access granted")
        }

        do {
            let events = try await eventService.recentStartedMeetings(
                withinDays: searchWindowDays,
                now: Date().addingTimeInterval(searchLookAhead)
            )
            let previous = meetings
            meetings = events.compactMap { event in
                guard var meeting = WBiOSMeeting(
                    from: event,
                    timeFormatter: timeFormatter,
                    dateFormatter: dateFormatter
                ) else {
                    return nil
                }
                // Preserve an already-resolved id for the same occurrence across refreshes, so the
                // optional `meetingID` state signal survives a non-forced reload.
                meeting.meetingID = previous.first { $0.id == meeting.id }?.meetingID
                return meeting
            }
            let eventCount = events.count
            let meetingCount = meetings.count
            WBLog.info("🔄🏠 load[\(source)] fetched \(eventCount) events → \(meetingCount) meetings")

            // Keep the user's current pick if it survived the refresh; else fall back to the latest.
            let display = meetings.first { $0.id == selectedID } ?? meetings.first
            if let display {
                let title = display.title
                WBLog.info("🔄🏠 load[\(source)] → loaded(\(title))")
                setDisplayed(display, force: force)
            } else {
                WBLog.info("🔄🏠 load[\(source)] → empty")
                clearDisplayed()
            }
        } catch {
            WBLog.error("⚠️🏠 load[\(source)] failed to load recent meetings: \(error)")
            state = .empty
        }
    }

    /// Replaces the displayed meeting with one the user picked from `meetings`.
    func select(_ meeting: WBiOSMeeting) {
        setDisplayed(meeting)
    }

    /// Single entry point for "this meeting is now displayed" — used by both auto-selection in
    /// `load()` and manual selection via `select(_:)`. Fires the selection hook only when the
    /// displayed meeting actually changes, so a refresh that keeps the same meeting won't re-trigger
    /// — unless `force` is set (pull-to-refresh), which re-fires regardless.
    private func setDisplayed(_ meeting: WBiOSMeeting, force: Bool = false) {
        let changed = meeting.id != selectedID
        state = .loaded(meeting)
        selectedID = meeting.id
        guard changed || force else { return }
        onMeetingSelected(meeting)
    }

    /// Clears the displayed meeting when there are no candidates.
    private func clearDisplayed() {
        state = .empty
        selectedID = nil
    }

    /// Fired once whenever the displayed meeting changes (auto or manual) — the single place to
    /// kick off background work for the selected meeting.
    private func onMeetingSelected(_ meeting: WBiOSMeeting) {
        enrichTask?.cancel()
        let eventUID = meeting.calendarItemExternalIdentifier
        let startEpoch = meeting.startEpoch
        let localID = meeting.id
        let title = meeting.title
        let attendeeCount = meeting.attendees.count
        WBLog.info("🎯🏠 meeting selected: \(title) — \(attendeeCount) attendee(s)")
        capturesState = .loading

        enrichTask = Task { [weak self] in
            guard let self else { return }
            do {
                WBLog.info("1️⃣🏠 Background step 1: resolve meetingID for \(eventUID)")
                let meetingID = try await syncService.resolveMeetingID(
                    eventUID: eventUID,
                    startEpoch: startEpoch
                )
                guard !Task.isCancelled else { return }
                applyMeetingID(meetingID, forLocalID: localID)

                WBLog.info("2️⃣🏠 Background step 2: load recent captures for meetingID \(meetingID)")
                await loadCaptures(meetingID: meetingID)
            } catch {
                guard !Task.isCancelled else { return }   // superseded by a newer selection — leave its state
                let description = "\(error)"
                WBLog.error("⚠️🎯🏠 meeting sync failed for \(eventUID): \(description)")
                capturesState = .loaded([])
            }
        }
    }

    /// Step 2: loads the displayed meeting's whiteboard captures (records only; photos stream in
    /// lazily per row). Surfaces `.iCloudUnavailable` when the photo container isn't reachable.
    private func loadCaptures(meetingID: String) async {
        guard contentLoader.isICloudAvailable else {
            capturesState = .iCloudUnavailable
            return
        }
        do {
            let records = try await contentLoader.recentCaptures(meetingID: meetingID)
            guard !Task.isCancelled else { return }
            let captures = records.map {
                WBiOSCapture(from: $0, formatter: captureTimestampFormatter)
            }
            let count = captures.count
            WBLog.info("🖼️🏠 Loaded \(count) capture(s) for meetingID \(meetingID)")
            capturesState = .loaded(captures)
        } catch {
            let description = "\(error)"
            WBLog.error("⚠️🖼️🏠 Failed to load captures for \(meetingID): \(description)")
            capturesState = .loaded([])
        }
    }

    /// Reloads the captures for the currently displayed meeting — e.g. after a new whiteboard is
    /// saved from the capture flow. No-op when no meeting is displayed. Existing rows stay until the
    /// reload completes (no spinner flash).
    ///
    /// Reloads a few times with short delays to absorb railengine's eventual consistency after an
    /// ingest; stops early once a new capture shows up, and bails if the displayed meeting changes.
    func refreshCaptures() {
        guard case .loaded(let meeting) = state else {
            return
        }
        let localID = meeting.id
        let meetingID = meeting.meetingID
            ?? WBMeetingID.mint(
                eventUID: meeting.calendarItemExternalIdentifier,
                startEpoch: meeting.startEpoch
            )
        let startingCount = capturesCount

        let delays: [Duration] = [.zero, .seconds(2), .seconds(5)]
        Task { [weak self] in
            for delay in delays {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                guard let self else { return }
                // Bail if the displayed meeting changed while we were retrying.
                guard case .loaded(let current) = state, current.id == localID else { return }
                await loadCaptures(meetingID: meetingID)
                // Stop once a new capture has appeared.
                if let count = capturesCount, let startingCount, count > startingCount {
                    return
                }
            }
        }
    }

    /// Number of loaded captures, or `nil` when not in the `.loaded` captures state.
    private var capturesCount: Int? {
        if case .loaded(let captures) = capturesState {
            return captures.count
        }
        return nil
    }

    /// Lazily resolves a capture's photo for display. Returns `nil` when the photo is missing or
    /// can't be loaded — the row then shows a placeholder.
    func captureImage(imageID: String) async -> UIImage? {
        do {
            guard let data = try await contentLoader.photoData(imageID: imageID) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            let description = "\(error)"
            WBLog.error("⚠️🖼️🏠 Failed to load photo \(imageID): \(description)")
            return nil
        }
    }

    /// Writes the resolved railengine `meetingID` back into the local model — both the candidate
    /// array copy and the currently-displayed copy. Main-actor isolated (the VM is `@MainActor`).
    private func applyMeetingID(_ meetingID: String, forLocalID localID: String) {
        if let index = meetings.firstIndex(where: { $0.id == localID }) {
            meetings[index].meetingID = meetingID
        }
        if case .loaded(var shown) = state, shown.id == localID {
            shown.meetingID = meetingID
            state = .loaded(shown)
        }
    }

    /// Opens the app's Settings page so the user can grant calendar access.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
