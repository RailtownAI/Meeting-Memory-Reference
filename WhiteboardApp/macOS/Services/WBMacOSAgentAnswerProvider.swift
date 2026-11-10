import Foundation
import WhiteboardCore

/// Answers a natural-language question from the user's captured meeting knowledge.
protocol WBMacOSAnswerProviding {
    func answer(toQuestion question: String) async throws -> WBMacOSAnswer
}

/// Real retrieval + agent: the core prompt-search agent answers with `{answer, ids}`, the record
/// store resolves the ids from railengine hot storage, and the wire records are adapted to
/// app-local models here at the provider layer. Related meetings get their personal title and
/// start time re-resolved on-device via EventKit.
struct WBMacOSAgentAnswerProvider: WBMacOSAnswerProviding {
    private let searchService = WBPromptSearchService()
    private let recordStore = WBWhiteboardRecordStore()
    private let meetingDetailProvider: WBMacOSMeetingDetailProviding = WBMacOSEventKitMeetingDetailProvider()

    func answer(toQuestion question: String) async throws -> WBMacOSAnswer {
        let result = try await searchService.search(prompt: question)
        let records = try await recordStore.records(ids: result.ids)
        let relatedMeetings = await resolvedRelatedMeetings(
            from: WBMacOSWhiteboardRecordAdapter.relatedMeetings(from: records)
        )
        let whiteboards = presentableWhiteboards(
            from: records.map { WBMacOSWhiteboardRecordAdapter.whiteboard(from: $0) },
            resolvedMeetings: relatedMeetings
        )
        return WBMacOSAnswer(
            question: question,
            text: result.answer,
            whiteboards: whiteboards,
            relatedMeetings: relatedMeetings
        )
    }
}

private extension WBMacOSAgentAnswerProvider {

    /// A whiteboard needs at least one anchor to be worth showing: its photo (present or
    /// still syncing in the iCloud container) or its calendar event (resolved on-device).
    /// Results with neither — e.g. records ingested from another device's environment —
    /// would render as empty shells, so they are dropped (logged).
    func presentableWhiteboards(
        from whiteboards: [WBMacOSWhiteboard],
        resolvedMeetings: [WBMacOSRelatedMeeting]
    ) -> [WBMacOSWhiteboard] {
        let resolvedEventIDs = Set(resolvedMeetings.compactMap(\.calendarEventID))
        return whiteboards.filter { whiteboard in
            if let imageID = whiteboard.imageID,
               (try? WBFileStore.photoExists(imageID: imageID)) == true {
                return true
            }
            if let calendarEventID = whiteboard.calendarEventID,
               resolvedEventIDs.contains(calendarEventID) {
                return true
            }
            WBLog.info(
                "Dropping whiteboard \(whiteboard.id) — no reachable photo and no resolvable calendar event"
            )
            return false
        }
    }

    /// Replaces each meeting's title and start with the on-device calendar data — the wire
    /// `title` is the whiteboard content title, not the meeting's. Meetings whose event
    /// can't be resolved in the user's calendar are dropped (logged): showing them would
    /// mean showing a content title masquerading as a meeting.
    func resolvedRelatedMeetings(
        from meetings: [WBMacOSRelatedMeeting]
    ) async -> [WBMacOSRelatedMeeting] {
        await withTaskGroup(of: (Int, WBMacOSRelatedMeeting?).self) { group in
            for (index, meeting) in meetings.enumerated() {
                group.addTask {
                    guard
                        let calendarEventID = meeting.calendarEventID,
                        let detail = try? await self.meetingDetailProvider.meetingDetail(
                            forCalendarEventID: calendarEventID,
                            occurrenceStart: meeting.startDate
                        )
                    else {
                        WBLog.info(
                            "Dropping related meeting \(meeting.id) — calendar event \(meeting.calendarEventID ?? "none") not resolvable on this device"
                        )
                        return (index, nil)
                    }
                    return (
                        index,
                        WBMacOSRelatedMeeting(
                            id: meeting.id,
                            title: detail.title,
                            startDate: detail.startDate,
                            calendarEventID: calendarEventID
                        )
                    )
                }
            }
            var indexedMeetings: [(index: Int, meeting: WBMacOSRelatedMeeting)] = []
            for await (index, meeting) in group {
                if let meeting {
                    indexedMeetings.append((index, meeting))
                }
            }
            return indexedMeetings
                .sorted { $0.index < $1.index }
                .map(\.meeting)
        }
    }
}
