//
//  WBMeetingID.swift
//  WhiteboardCore
//

import Foundation

/// Deterministic meeting identity shared by the read and write paths — and by both apps.
///
/// A meeting occurrence is `"<eventUID>#<startEpoch>"`: human-readable and reproducible, so iOS
/// (which ingests) and macOS (which only retrieves) mint the identical id and resolve the same
/// railengine record. `eventUID` is the calendar event's `calendarItemExternalIdentifier`;
/// `startEpoch` is the occurrence start in whole seconds since 1970 (second precision is plenty for
/// meeting granularity).
///
/// Kept human-readable for now; swap the body for an encoded/hashed form if a raw `eventUID` ever
/// trips the engine's id constraints (length, or the `$.meetingId:<value>` query delimiter).
public enum WBMeetingID {
    public static func mint(eventUID: String, startEpoch: Int) -> String {
        "\(eventUID)#\(startEpoch)"
    }
}
