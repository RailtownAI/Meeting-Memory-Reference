//
//  WBAskAboutMeetingToolIntent.swift
//  WhiteboardApp
//
//  A tool Siri's model can call (27.3) about one calendar meeting, usually the one on screen in
//  Calendar: finds it in EventKit and answers with the whiteboards captured in its earlier
//  occurrences.
//

import AppIntents
import Foundation
import WhiteboardCore

@available(iOS 27.3, macOS 27.3, *)
@AppIntent(.tool)
struct WBAskAboutMeetingToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About a Meeting"
    static let description = IntentDescription(
        "Prepares the user for a calendar meeting, or answers a question about it, from the whiteboards captured in earlier occurrences of that meeting. Returns plain text: the meeting, then each whiteboard with its meeting date in full, its summary, and its action items as sentences."
    )

    @Parameter(
        title: "Meeting Title",
        description: "The title of the calendar meeting the person is looking at on screen, for example in Calendar, or the meeting they name."
    )
    var meetingTitle: String?

    @Parameter(
        title: "Meeting Start",
        description: "The start date and time of that meeting, as shown on screen."
    )
    var meetingStart: Date?

    @Parameter(
        title: "Question",
        description: "What the person wants to know about the meeting. Leave empty to prepare a briefing."
    )
    var question: String?

    @Dependency private var recordStore: WBWhiteboardRecordStore
    @Dependency private var eventService: WBEventKitService

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        WBIntentReply.result(
            await Self.answer(
                meetingTitle: meetingTitle,
                meetingStart: meetingStart,
                question: question,
                eventService: eventService,
                recordStore: recordStore
            )
        )
    }

    /// The reply as one plain string: the question (if any), the meeting, then up to
    /// `maximumWhiteboards` of its whiteboards, newest first. Never throws; failures become a
    /// sentence that says what to do.
    ///
    /// Static, so it can run without the system's intent runner.
    static func answer(
        meetingTitle: String?,
        meetingStart: Date?,
        question: String?,
        eventService: WBEventKitService,
        recordStore: WBWhiteboardRecordStore,
        now: Date = Date()
    ) async -> String {
        let title = meetingTitle.flatMap(Self.nonEmpty)
        let question = question.flatMap(Self.nonEmpty)
        // Shows what Siri passed in, e.g. the title and start it read from an event on screen.
        let received = "title \(title.map { "\"\($0)\"" } ?? "none"), "
            + "start \(meetingStart?.ISO8601Format() ?? "none"), "
            + "question \(question.map { "\"\($0)\"" } ?? "none")"
        WBLog.info("🗣️ Meeting tool received \(received)")

        // Never prompts: Siri runs this in the background, where a prompt can't be answered.
        guard eventService.hasFullAccess else {
            WBLog.info("🗣️ Meeting tool has no full calendar access; answered without a lookup")
            return "Open Meeting Memory once and allow Calendar access, then ask again."
        }
        do {
            return try await withDeadline(seconds: WBIntentReply.waitSeconds) {
                let resolution = try await resolveEvent(
                    title: title,
                    start: meetingStart,
                    eventService: eventService,
                    now: now
                )
                let path = resolution.path
                guard let event = resolution.event else {
                    WBLog.info("🗣️ Meeting tool found no event (looked up by \(path))")
                    return notFound(title: title, start: meetingStart)
                }
                let occurrences = try await whiteboards(
                    of: event,
                    eventService: eventService,
                    recordStore: recordStore
                )
                let eventText = "\"\(event.title)\" at \(event.startDate.ISO8601Format())"
                let whiteboardCount = occurrences.reduce(0) { $0 + $1.records.count }
                WBLog.info(
                    "🗣️ Meeting tool found \(eventText) by \(path): \(whiteboardCount) whiteboard(s) in \(occurrences.count) occurrence(s)"
                )
                return text(event: event, question: question, occurrences: occurrences)
            }
        } catch is WBDeadlineExceeded {
            WBLog.warning("⚠️🗣️ Meeting tool passed its \(WBIntentReply.waitSeconds)s deadline")
            return "Meeting Memory is taking longer than usual to load that meeting's whiteboards. Ask again in a moment."
        } catch {
            return WBIntentReply.message(for: error, action: "load that meeting's whiteboards")
        }
    }
}

// MARK: - Finding the meeting

@available(iOS 27.3, macOS 27.3, *)
extension WBAskAboutMeetingToolIntent {
    /// How far either side of Siri's start a meeting is looked for, beyond the start's whole day
    /// (a date read without its time comes as midnight): covers a time read in another time zone.
    static nonisolated let startSearchHours: Double = 12

    /// How far back earlier occurrences of the meeting are read.
    static nonisolated let historyDays = 90

    /// The most occurrences whose whiteboards are loaded: each is an engine query, and a daily
    /// meeting has about 65 in `historyDays`.
    static nonisolated let maximumOccurrences = 20

    /// The most whiteboards in a reply.
    static nonisolated let maximumWhiteboards = 4

    /// The event Siri meant, and which lookup found it (for the log).
    ///
    /// - Start (with or without a title): events on its day or within `startSearchHours` of it;
    ///   with a title, only those whose title matches either way; the one starting closest to it.
    /// - Title only: matching meetings within a week of `now`; the one in progress, else the next
    ///   one, else the latest past one.
    static nonisolated func resolveEvent(
        title: String?,
        start: Date?,
        eventService: WBEventKitService,
        now: Date
    ) async throws -> (event: WBCalendarEvent?, path: String) {
        if let start {
            let window = startSearchHours * 3600
            let day = Calendar.current.startOfDay(for: start)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
            let events = try await eventService.events(
                from: min(day, start.addingTimeInterval(-window)),
                to: max(dayEnd, start.addingTimeInterval(window))
            )
            let candidates = events
                .filter(WBMeetingMatcher.isCandidate)
                .filter { event in
                    guard let title else {
                        return true
                    }
                    return WBMeetingMatcher.title(event.title, matches: title, eitherWay: true)
                }
            let closest = candidates.min {
                abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start))
            }
            return (closest, title == nil ? "start" : "title+start")
        }
        guard let title else {
            return (nil, "none")
        }
        let meetings = try await eventService.meetings(titled: title, around: now, eitherWay: true)
        let inProgress = meetings.first { $0.startDate <= now && $0.endDate > now }
        let next = meetings.first { $0.startDate > now }
        let latestPast = meetings.last { $0.endDate <= now }
        return (inProgress ?? next ?? latestPast, "title")
    }

    /// "I could not find a meeting titled "Design review" on Thursday, November 12, 2026 at 10:00
    /// AM in Calendar."
    static nonisolated func notFound(title: String?, start: Date?) -> String {
        switch (title, start) {
        case let (title?, start?):
            return "I could not find a meeting titled \"\(title)\" on \(fullDateTime(start)) in Calendar."
        case let (title?, nil):
            return "I could not find a meeting titled \"\(title)\" in the past or next week in Calendar."
        case let (nil, start?):
            return "I could not find a meeting around \(fullDateTime(start)) in Calendar."
        case (nil, nil):
            return "I need the meeting's title or start time to find it in Calendar. Open the meeting in Calendar, or name it, and ask again."
        }
    }
}

// MARK: - Loading the whiteboards

@available(iOS 27.3, macOS 27.3, *)
extension WBAskAboutMeetingToolIntent {
    /// One occurrence of the meeting and its whiteboards, most recent capture first.
    nonisolated struct Occurrence: Sendable {
        let start: Date
        let records: [WBWhiteboardRecord]
    }

    /// `event` and its earlier occurrences within `historyDays`, newest first, each with its
    /// whiteboards; occurrences without whiteboards are left out.
    ///
    /// Occurrences come from a date-range fetch filtered by external identifier, not
    /// `events(withExternalIdentifier:)`, which can answer with only a recurring event's first
    /// occurrence. Each meeting id is minted from the occurrence's own EventKit start, never from
    /// Siri's date, so it is the id iOS minted when the whiteboard was saved.
    static nonisolated func whiteboards(
        of event: WBCalendarEvent,
        eventService: WBEventKitService,
        recordStore: WBWhiteboardRecordStore
    ) async throws -> [Occurrence] {
        guard let eventUID = event.externalIdentifier else {
            return []
        }
        let from = event.startDate.addingTimeInterval(-Double(historyDays) * 86_400)
        let history = try await eventService
            .events(from: from, to: event.startDate.addingTimeInterval(1))
            .filter { $0.externalIdentifier == eventUID }
        // The same identifier can appear in several calendars; one occurrence per start.
        var starts = Set([Int(event.startDate.timeIntervalSince1970)])
        for occurrence in history {
            starts.insert(Int(occurrence.startDate.timeIntervalSince1970))
        }
        let newest = starts.sorted(by: >).prefix(maximumOccurrences)
        return try await withThrowingTaskGroup(of: Occurrence.self) { group in
            for startEpoch in newest {
                group.addTask {
                    let meetingID = WBMeetingID.mint(eventUID: eventUID, startEpoch: startEpoch)
                    let records = try await recordStore.records(meetingID: meetingID)
                        .sorted { $0.capturedAtEpoch > $1.capturedAtEpoch }
                    return Occurrence(
                        start: Date(timeIntervalSince1970: TimeInterval(startEpoch)),
                        records: records
                    )
                }
            }
            var occurrences: [Occurrence] = []
            for try await occurrence in group where !occurrence.records.isEmpty {
                occurrences.append(occurrence)
            }
            return occurrences.sorted { $0.start > $1.start }
        }
    }
}

// MARK: - The reply

@available(iOS 27.3, macOS 27.3, *)
extension WBAskAboutMeetingToolIntent {
    /// The longest a whiteboard's summary gets in a reply.
    static nonisolated let maximumSummaryLength = 300

    /// The longest a whiteboard's paragraph (title, summary, action items) gets in a reply.
    static nonisolated let maximumWhiteboardLength = 400

    /// The longest a reply gets; whiteboards that would pass it are left out.
    static nonisolated let maximumReplyLength = 1500

    /// "Question: What did we decide? Answer it from these whiteboard notes.
    ///
    /// Notes for Design review, Thursday, November 12, 2026 at 10:00 AM. 2 whiteboards from this
    /// meeting, newest first.
    ///
    /// From the Thursday, November 5, 2026 meeting: "Roadmap". Summary. Action items: Send the
    /// deck to Sam."
    static nonisolated func text(
        event: WBCalendarEvent,
        question: String?,
        occurrences: [Occurrence]
    ) -> String {
        let whiteboards = occurrences.flatMap { occurrence in
            occurrence.records.map { (start: occurrence.start, record: $0) }
        }
        guard !whiteboards.isEmpty else {
            return "No whiteboards are saved for \(event.title) yet."
        }
        var header: [String] = []
        if let question {
            header.append("Question: \(WBIntentReply.sentence(question)) Answer it from these whiteboard notes.")
        }
        // The header's count line is under 150 characters; the first whiteboard always goes in.
        var length = header.joined(separator: "\n\n").count + 150
        var notes: [String] = []
        for (start, record) in whiteboards.prefix(maximumWhiteboards) {
            let paragraph = truncated(
                whiteboardText(record, meetingStart: start),
                to: maximumWhiteboardLength
            )
            guard notes.isEmpty || length + paragraph.count + 2 <= maximumReplyLength else {
                break
            }
            notes.append(paragraph)
            length += paragraph.count + 2
        }
        let count = notes.count == 1 ? "1 whiteboard" : "\(notes.count) whiteboards"
        let purpose = question == nil ? "Briefing for" : "Notes for"
        header.append(
            "\(purpose) \(event.title), \(fullDateTime(event.startDate)). \(count) from this meeting, newest first."
        )
        return (header + notes).joined(separator: "\n\n")
    }

    /// "From the Thursday, November 5, 2026 meeting: "Roadmap". Summary. Action items: Send the
    /// deck to Sam."
    static nonisolated func whiteboardText(
        _ record: WBWhiteboardRecord,
        meetingStart: Date
    ) -> String {
        var line = "From the \(WBIntentReply.fullDate(meetingStart)) meeting"
        line += record.title.isEmpty ? "." : ": \"\(record.title)\"."
        let summary = WBIntentReply.plain(record.summary)
        if !summary.isEmpty {
            line += " " + WBIntentReply.sentence(truncated(summary, to: maximumSummaryLength))
        }
        let actionItems = record.actionItems.map(\.text).filter { !$0.isEmpty }
        if !actionItems.isEmpty {
            line += " Action items: " + actionItems.map(WBIntentReply.sentence).joined(separator: " ")
        }
        return line
    }

    /// `text` cut to `length` characters at a word, with an ellipsis.
    static nonisolated func truncated(_ text: String, to length: Int) -> String {
        guard text.count > length else {
            return text
        }
        let prefix = text.prefix(length)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    /// "Thursday, November 12, 2026 at 10:00 AM".
    static nonisolated func fullDateTime(_ date: Date) -> String {
        "\(WBIntentReply.fullDate(date)) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// `text` trimmed, or `nil` when that leaves nothing: Siri may pass an empty string for a
    /// parameter it could not fill.
    static nonisolated func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
