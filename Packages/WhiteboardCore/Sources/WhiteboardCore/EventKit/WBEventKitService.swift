import EventKit

/// Read-only EventKit access shared by the iOS and macOS apps.
///
/// Lookup by `calendarItemExternalIdentifier` is the interesting part for the whiteboard flow:
/// unlike `eventIdentifier`, the external identifier is stable across devices and calendar
/// databases, so an identifier captured on one device can be resolved back to the full event on
/// another.
///
/// An actor so the `EKEventStore` and its (potentially slow) synchronous fetches run off the
/// callers' threads, and so the service is `Sendable`.
public actor WBEventKitService {
    public enum WBEventKitError: LocalizedError, CustomStringConvertible {
        case accessDenied

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Calendar access is not granted — allow full access in Settings."
            }
        }

        /// Without this, `String(describing:)` renders the bare case name — `accessDenied` — and
        /// that is what anything logging or reporting this error shows, including the exception
        /// headline uploaded to Conductr. Mirrors Conduit's `AIError`, whose `description` is its
        /// `errorDescription`, so a reported failure reads as a sentence rather than an identifier.
        public var description: String {
            errorDescription ?? "Calendar access is not granted."
        }
    }

    /// A single events predicate silently caps its range at 4 years, so wide fetches are chunked.
    private static let maximumPredicateYears = 4

    private let store = EKEventStore()

    public init() {}

    /// Current calendar authorization. `.fullAccess` is required to read events; `.writeOnly`
    /// (the iOS 17+ "add events only" grant) is not enough.
    ///
    /// Nonisolated: this reads process-wide EventKit state, not actor state, so callers can
    /// check it synchronously.
    public nonisolated var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    public nonisolated var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    /// Whether the user hasn't been asked for calendar access yet — i.e. `requestFullAccess()`
    /// would show the system prompt rather than silently return the standing answer. Mirrors
    /// `WBContactPhotoService.canRequestAccess`, and spares callers an `EventKit` import to compare
    /// against `EKAuthorizationStatus`.
    public nonisolated var canRequestAccess: Bool {
        authorizationStatus == .notDetermined
    }

    /// Prompts for full read access to the user's calendars. Returns whether access was granted.
    ///
    /// A refusal is reported to the Railtown platform — see `WBPermissionReporter`, which keeps it
    /// to one report per launch. Reported from here rather than from each screen so both apps are
    /// covered by one call, and so the prompt-or-not distinction is drawn where it's still knowable:
    /// once this returns, a fresh refusal and a standing one are indistinguishable.
    public func requestFullAccess() async throws -> Bool {
        let canPrompt = canRequestAccess
        let isGranted = try await store.requestFullAccessToEvents()
        if !isGranted {
            WBPermissionReporter.reportDenied(
                .calendar,
                canPrompt ? .deniedAtPrompt : .deniedBeforeLaunch
            )
        }
        return isGranted
    }

    /// The user's calendars that can contain events.
    public func calendars() -> [WBCalendarEvent.CalendarInfo] {
        store.calendars(for: .event).map(WBCalendarEvent.CalendarInfo.init)
    }

    /// Every event in the date range, sorted by start date — across all calendars, or only the
    /// ones whose `CalendarInfo.identifier` is given. Ranges wider than EventKit's 4-year
    /// predicate limit are fetched in chunks.
    public func events(
        from startDate: Date,
        to endDate: Date,
        inCalendarsWithIdentifiers calendarIdentifiers: Set<String>? = nil
    ) throws -> [WBCalendarEvent] {
        guard hasFullAccess else {
            // Covers a caller that reads without ever prompting; no prompt was shown here, so the
            // denial was already standing.
            WBPermissionReporter.reportDenied(.calendar, .deniedBeforeLaunch)
            throw WBEventKitError.accessDenied
        }
        let calendars = calendarIdentifiers.map { identifiers in
            store.calendars(for: .event)
                .filter { identifiers.contains($0.calendarIdentifier) }
        }
        var events: [EKEvent] = []
        var windowStart = startDate
        while windowStart < endDate {
            let windowEnd = min(
                Calendar.current.date(
                    byAdding: .year,
                    value: Self.maximumPredicateYears,
                    to: windowStart
                ) ?? endDate,
                endDate
            )
            let predicate = store.predicateForEvents(
                withStart: windowStart,
                end: windowEnd,
                calendars: calendars
            )
            events.append(contentsOf: store.events(matching: predicate))
            windowStart = windowEnd
        }
        return events
            .map(WBCalendarEvent.init)
            .sorted { $0.startDate < $1.startDate }
    }

    /// Resolves a `calendarItemExternalIdentifier` to its events. Can return multiple items —
    /// the same external identifier may appear in several calendars (e.g. an invite in both a
    /// personal and a delegate calendar) — and returns an empty array when nothing matches.
    public func events(withExternalIdentifier identifier: String) throws -> [WBCalendarEvent] {
        guard hasFullAccess else {
            // Covers a caller that reads without ever prompting; no prompt was shown here, so the
            // denial was already standing.
            WBPermissionReporter.reportDenied(.calendar, .deniedBeforeLaunch)
            throw WBEventKitError.accessDenied
        }
        return store.calendarItems(withExternalIdentifier: identifier)
            .compactMap { $0 as? EKEvent }
            .map(WBCalendarEvent.init)
    }

    /// Real meetings that have already **started** within the last `days`, sorted latest-start first.
    ///
    /// A caller typically takes `.first` as the "current/most-recent meeting" and keeps the full
    /// list for manual swapping. Deliberately excluded (and worth remembering when reading this):
    /// - **future** events (start after now),
    /// - **all-day** events,
    /// - events the current user **declined**, and **canceled** events,
    /// - events on **birthday** and **subscription** calendars (the latter covers Holidays and other
    ///   subscribed calendars).
    ///
    /// Availability (busy/free) is intentionally *not* used as a filter. When more than one meeting
    /// shares the same latest start (a double-booking), all are kept and a warning is logged — the
    /// caller picks the first.
    ///
    /// `now` is injectable (defaults to the current time) — handy for deterministic tests and to make
    /// future look-ahead leniency easy (e.g. also counting meetings that start within the next N min).
    public func recentStartedMeetings(
        withinDays days: Int,
        now: Date = Date()
    ) throws -> [WBCalendarEvent] {
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return []
        }
        let fetched = try events(from: windowStart, to: now)
        WBLog.trace("🔎📅 Fetched \(fetched.count) events in the past \(days)d: \(fetched)")
        let candidates = fetched
            .filter { $0.startDate >= windowStart && $0.startDate <= now }
            .filter(Self.isRealMeeting)
            .sorted { $0.startDate > $1.startDate }

        if let latestStart = candidates.first?.startDate {
            let tiedForLatest = candidates.prefix { $0.startDate == latestStart }
            if tiedForLatest.count > 1 {
                WBLog.warning(
                    "⚠️📅 \(tiedForLatest.count) meetings share the latest start time — using the first"
                )
            }
        }
        return candidates
    }

    /// Whether an event counts as a real, attendable meeting for the "recent meeting" logic.
    private static func isRealMeeting(_ event: WBCalendarEvent) -> Bool {
        guard !event.isAllDay else {
            return false
        }
        guard event.status != .canceled else {
            return false
        }
        if let type = event.calendar?.type, type == .birthday || type == .subscription {
            return false
        }
        let declinedByCurrentUser = event.attendees.contains {
            $0.isCurrentUser && $0.status == .declined
        }
        return !declinedByCurrentUser
    }
}
