//
//  WBWhiteboardSpotlight.swift
//  WhiteboardApp
//
//  Puts whiteboard entities in Spotlight, where Siri and Spotlight find them by their text.
//

import AppIntents
import CoreSpotlight
import Foundation
import WhiteboardCore

enum WBWhiteboardSpotlight {
    /// A named index, so the app's whiteboards can be cleared or rebuilt without touching anything
    /// else the system indexed for the app.
    static let searchableIndex = CSSearchableIndex(name: "MeetingMemory.Whiteboards")

    /// How many whiteboards the launch sync reads at most.
    private static let launchSyncLimit = 200

    /// The engine's largest page, so the launch sync lists in the fewest requests.
    private static let launchSyncPageSize = 100

    /// How long the launch sync trusts its own table of indexed versions. After this it indexes
    /// everything once more, which repairs an index the system cleared and picks up meeting titles
    /// that changed in the calendar.
    private static let fullSyncInterval: TimeInterval = 7 * 24 * 3600

    /// `[record id: engine version]` for the whiteboards the launch sync indexed on this device.
    private static let indexedVersionsKey = "ai.railtown.whiteboard.spotlight-indexed-versions"

    /// When the launch sync last indexed everything.
    private static let lastFullSyncKey = "ai.railtown.whiteboard.spotlight-last-full-sync"

    /// Adds or updates `entities` in the index, and returns whether that worked. A failure is
    /// logged, never thrown: Spotlight is a convenience on top of a save or a list that already
    /// succeeded.
    @discardableResult
    static func index(_ entities: [WBWhiteboardEntity]) async -> Bool {
        guard !entities.isEmpty else {
            return true
        }
        let count = entities.count
        do {
            try await searchableIndex.indexAppEntities(entities)
            WBLog.info("🔦 Indexed \(count) whiteboard(s) in Spotlight")
            return true
        } catch {
            let description = "\(error)"
            WBLog.warning("⚠️🔦 Spotlight indexing failed for \(count) whiteboard(s): \(description)")
            return false
        }
    }

    /// Indexes one record that was just saved, with the meeting title the caller already has.
    static func index(_ record: WBWhiteboardRecord, meetingTitle: String?) async {
        await index([WBWhiteboardEntity(record: record, meetingTitle: meetingTitle)])
    }

    /// Indexes the whiteboards that are new or changed since the last sync on this device, out of
    /// about `launchSyncLimit`, walking the store's pages. Used at Mac launch: the Mac only reads
    /// records, so this is how captures from the iPhone reach its Spotlight. Missing keys or
    /// network just leave the index as it was.
    ///
    /// A whiteboard counts as changed when the engine's version for it differs from the version
    /// indexed last, which also covers an edit to its action items. Once per `fullSyncInterval`
    /// everything is indexed again.
    static func syncLatest() async {
        let store = WBWhiteboardRecordStore()
        // The highest version of each record: a list can hold more than one version of a record.
        var latest: [String: WBWhiteboardRecordStore.VersionedRecord] = [:]
        var listedEverything = true
        var pageNumber = 1
        do {
            while latest.count < launchSyncLimit {
                let page = try await store.listVersioned(
                    pageNumber: pageNumber,
                    pageSize: launchSyncPageSize
                )
                for item in page.items {
                    if let known = latest[item.record.id], known.version >= item.version {
                        continue
                    }
                    latest[item.record.id] = item
                }
                guard pageNumber < page.totalPages, !page.items.isEmpty else {
                    break
                }
                pageNumber += 1
            }
        } catch {
            listedEverything = false
            let description = "\(error)"
            WBLog.warning("⚠️🔦 Spotlight sync could not list whiteboards: \(description)")
        }

        let defaults = UserDefaults.standard
        let stored = defaults.dictionary(forKey: indexedVersionsKey) as? [String: Int]
        var indexedVersions = stored ?? [:]
        let lastFullSync = defaults.object(forKey: lastFullSyncKey) as? Date
        let sinceFullSync = lastFullSync.map { Date().timeIntervalSince($0) }
        let isFullSync = sinceFullSync.map { $0 > fullSyncInterval } ?? true
        let changed = latest.values.filter { item in
            isFullSync || indexedVersions[item.record.id] != item.version
        }
        guard !changed.isEmpty else {
            // Not after a failed list: that already logged a warning, and nothing was compared.
            if listedEverything {
                let listed = latest.count
                WBLog.info("🔦 Spotlight is up to date: \(listed) whiteboard(s), none changed")
            }
            return
        }
        // Recorded only after the index took them, so a failed run is tried again at next launch.
        guard await index(WBWhiteboardEntity.make(from: changed.map(\.record))) else {
            return
        }
        for item in changed {
            indexedVersions[item.record.id] = item.version
        }
        defaults.set(indexedVersions, forKey: indexedVersionsKey)
        if isFullSync, listedEverything {
            defaults.set(Date(), forKey: lastFullSyncKey)
        }
    }
}
