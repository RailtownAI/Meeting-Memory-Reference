import Foundation
import WhiteboardCore

/// iOS-only orchestration that links a displayed meeting to its railengine calendar record.
///
/// An `actor`, so it runs off the main actor and serializes its work (its "own queue"). Ingest lives
/// here because only iOS ingests; macOS reuses the Core retrieval stores directly. Part 2 (loading
/// whiteboard records + their photos) will move into a shared Core `WBMeetingContentLoader`.
actor WBiOSMeetingSyncService {
    private let eventService = WBEventKitService()
    private let calendarRecords = WBCalendarRecordStore()
    private let calendarIngestion = WBCalendarIngestionStore()

    /// Returns the `meetingID` for the occurrence, ingesting a new PII-free calendar record first if
    /// railengine doesn't have one yet. The id is minted deterministically from `eventUID` +
    /// `startEpoch`, so this is idempotent and reproducible across devices.
    func resolveMeetingID(eventUID: String, startEpoch: Int) async throws -> String {
        let meetingID = WBMeetingID.mint(eventUID: eventUID, startEpoch: startEpoch)

        // (1) retrieval attempt + (2) retrieval result
        WBLog.info("🔎📅 Retrieving calendar record for meetingID \(meetingID)")
        if let existing = try await calendarRecords.record(meetingID: meetingID) {
            WBLog.info("✅📅 Retrieval hit for meetingID \(meetingID) — using existing record")
            WBLog.trace("🔎📅 Retrieved calendar record: \(existing)")
            // TODO: verify `existing` against the current EventKit details (title / start-end /
            // location / recurrence) and re-ingest an updated record when they diverge, so a meeting
            // edited after its first ingest stays in true sync. For now we trust the stored record.
            return meetingID
        }
        WBLog.info("➖📅 Retrieval miss for meetingID \(meetingID) — will ingest")

        guard let record = try await makeRecord(
            meetingID: meetingID,
            eventUID: eventUID,
            startEpoch: startEpoch
        ) else {
            // No matching occurrence in EventKit (event deleted, or not on this device) — nothing to
            // ingest. Still return the id so callers can proceed; retrieval will simply find nothing.
            WBLog.warning("⚠️🔄 No EventKit occurrence for \(eventUID) @ \(startEpoch); skipping ingest")
            return meetingID
        }

        // (3) ingestion attempt + (4) ingestion result
        WBLog.info("📤📅 Ingesting calendar record for meetingID \(meetingID)")
        do {
            try await calendarIngestion.upsert(record)
            WBLog.info("✅📤 Ingestion succeeded for meetingID \(meetingID)")
        } catch {
            let description = "\(error)"
            WBLog.error("⚠️📤 Ingestion failed for meetingID \(meetingID): \(description)")
            throw error
        }
        return meetingID
    }

    /// Builds a PII-free `WBCalendarRecord` from the EventKit occurrence whose start matches
    /// `startEpoch`. `organizerRef`/`participantRefs` are intentionally empty — people are always
    /// re-resolved on-device from EventKit at display time.
    private func makeRecord(
        meetingID: String,
        eventUID: String,
        startEpoch: Int
    ) async throws -> WBCalendarRecord? {
        let events = try await eventService.events(withExternalIdentifier: eventUID)
        guard let event = events.first(where: {
            Int($0.startDate.timeIntervalSince1970) == startEpoch
        }) else {
            return nil
        }

        let iso = ISO8601DateFormatter()
        return WBCalendarRecord(
            id: meetingID,
            meetingId: meetingID,
            eventUID: eventUID,
            calendarId: event.calendar?.identifier ?? "",
            title: event.title,
            description: event.notes ?? "",
            isRecurring: event.hasRecurrenceRules,
            occurrenceStart: iso.string(from: event.startDate),
            occurrenceEnd: iso.string(from: event.endDate),
            startEpoch: Int(event.startDate.timeIntervalSince1970),
            endEpoch: Int(event.endDate.timeIntervalSince1970),
            timeZone: event.timeZone?.identifier ?? TimeZone.current.identifier,
            organizerRef: "",
            participantRefs: []
        )
    }
}
