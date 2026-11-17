//
//  WBWhiteboardEntity.swift
//  WhiteboardApp
//
//  A captured whiteboard as Siri, Shortcuts and Spotlight see it.
//

import AppIntents
import CoreSpotlight
import Foundation
import WhiteboardCore

/// A captured whiteboard, built from a `WBWhiteboardRecord`.
///
/// `id` is the record's UUID, the same on every device, so an entity found on the Mac resolves on
/// the iPhone too. The summary and action items are properties so Siri can read and pass them on,
/// for example an action item to Reminders.
struct WBWhiteboardEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Whiteboard",
        numericFormat: "\(placeholder: .int) whiteboards"
    )

    static let defaultQuery = WBWhiteboardEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Summary")
    var summary: String

    @Property(title: "Action Items")
    var actionItems: [String]

    @Property(title: "Captured")
    var capturedAt: Date

    @Property(title: "Meeting")
    var meetingTitle: String?

    @Property(title: "Meeting Start")
    var meetingStart: Date?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitleText)",
            image: .init(systemName: "rectangle.and.pencil.and.ellipsis")
        )
    }

    /// Capture date, and the meeting when it is known: "Nov 12, 2026 · Design review".
    var subtitleText: String {
        let date = capturedAt.formatted(date: .abbreviated, time: .omitted)
        guard let meetingTitle, !meetingTitle.isEmpty else {
            return date
        }
        return "\(date) · \(meetingTitle)"
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentDescription = summary
        attributes.textContent = ([summary] + actionItems).joined(separator: "\n")
        attributes.contentCreationDate = capturedAt
        attributes.keywords = ["whiteboard", "meeting"] + [meetingTitle].compactMap { $0 }
        return attributes
    }

    init(record: WBWhiteboardRecord, meetingTitle: String?) {
        let iso = ISO8601DateFormatter()
        id = record.id
        title = record.title.isEmpty ? "Untitled whiteboard" : record.title
        summary = record.summary
        actionItems = record.actionItems.map(\.text)
        capturedAt = iso.date(from: record.capturedAt)
            ?? Date(timeIntervalSince1970: TimeInterval(record.capturedAtEpoch))
        self.meetingTitle = meetingTitle
        meetingStart = iso.date(from: record.occurrenceStart)
    }

    /// Entities for `records`, in order, with meeting titles read from the calendar on this device.
    static func make(from records: [WBWhiteboardRecord]) async -> [WBWhiteboardEntity] {
        let titles = await WBMeetingTitles.titles(for: records)
        return records.map { record in
            WBWhiteboardEntity(record: record, meetingTitle: titles[record.meetingId])
        }
    }
}

/// Finds whiteboards for Siri and Shortcuts: by id, by text (semantic search), and the latest ones
/// as suggestions.
struct WBWhiteboardEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WBWhiteboardEntity] {
        let records = try await WBWhiteboardRecordStore().records(ids: identifiers)
        return await WBWhiteboardEntity.make(from: records)
    }

    func entities(matching string: String) async throws -> [WBWhiteboardEntity] {
        let records = try await WBWhiteboardRecordStore().search(query: string)
        return await WBWhiteboardEntity.make(from: records)
    }

    func suggestedEntities() async throws -> [WBWhiteboardEntity] {
        let page = try await WBWhiteboardRecordStore().list()
        let entities = await WBWhiteboardEntity.make(from: page.items)
        #if os(macOS)
        // The Mac never saves a whiteboard, so listing is where it learns about new ones.
        await WBWhiteboardSpotlight.index(entities)
        #endif
        return entities
    }
}

/// Marks the record UUID as the same entity on every device (Siri on iOS and macOS 27).
@available(iOS 27, macOS 27, *)
extension WBWhiteboardEntity: SyncableEntity {}

/// Meeting titles for whiteboard records, read from EventKit on this device.
///
/// Records carry only the meeting's calendar identifier and start, not its title, so the title is
/// looked up locally. Without calendar access, or for an event this device doesn't have, there is
/// simply no title.
enum WBMeetingTitles {
    /// Titles keyed by `WBWhiteboardRecord.meetingId`.
    static func titles(for records: [WBWhiteboardRecord]) async -> [String: String] {
        let eventService = WBEventKitService()
        guard eventService.hasFullAccess else {
            return [:]
        }
        let iso = ISO8601DateFormatter()
        // One calendar lookup per event: a recurring meeting's occurrences share an `eventUID`, and
        // an event this device doesn't have is not asked for again.
        var eventsByUID: [String: [WBCalendarEvent]] = [:]
        var titles: [String: String] = [:]
        for record in records where titles[record.meetingId] == nil && !record.eventUID.isEmpty {
            let events: [WBCalendarEvent]
            if let known = eventsByUID[record.eventUID] {
                events = known
            } else {
                let found = try? await eventService.events(withExternalIdentifier: record.eventUID)
                events = found ?? []
                eventsByUID[record.eventUID] = events
            }
            let start = iso.date(from: record.occurrenceStart)
            let event = events.first { event in
                start.map { Int(event.startDate.timeIntervalSince1970) == Int($0.timeIntervalSince1970) } ?? false
            } ?? events.first
            if let event {
                titles[record.meetingId] = event.title
            }
        }
        return titles
    }
}
