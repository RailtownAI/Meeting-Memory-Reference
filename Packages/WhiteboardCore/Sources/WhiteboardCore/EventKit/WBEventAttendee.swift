import EventKit

/// Value snapshot of an `EKParticipant` (event organizer or attendee).
public struct WBEventAttendee: Identifiable, Sendable {
    public enum Role: String, Sendable {
        case unknown, required, optional, chair, nonParticipant

        init(_ role: EKParticipantRole) {
            switch role {
            case .required: self = .required
            case .optional: self = .optional
            case .chair: self = .chair
            case .nonParticipant: self = .nonParticipant
            case .unknown: self = .unknown
            @unknown default: self = .unknown
            }
        }
    }

    public enum Status: String, Sendable {
        case unknown, pending, accepted, declined, tentative, delegated, completed, inProcess

        init(_ status: EKParticipantStatus) {
            switch status {
            case .pending: self = .pending
            case .accepted: self = .accepted
            case .declined: self = .declined
            case .tentative: self = .tentative
            case .delegated: self = .delegated
            case .completed: self = .completed
            case .inProcess: self = .inProcess
            case .unknown: self = .unknown
            @unknown default: self = .unknown
            }
        }
    }

    public enum Kind: String, Sendable {
        case unknown, person, room, resource, group

        init(_ type: EKParticipantType) {
            switch type {
            case .person: self = .person
            case .room: self = .room
            case .resource: self = .resource
            case .group: self = .group
            case .unknown: self = .unknown
            @unknown default: self = .unknown
            }
        }
    }

    public let name: String?
    /// Participant URL, typically `mailto:someone@example.com`.
    public let url: URL
    public let role: Role
    public let status: Status
    public let kind: Kind
    public let isCurrentUser: Bool

    public var id: URL { url }

    /// The participant's email address: the `mailto:` URL's address part (without any
    /// `?header` suffix), or — for backends that hand back a non-mailto participant URL —
    /// a display name that is itself an address. `nil` (with a warning at mapping time)
    /// when neither yields a **valid** address — e.g. the current user's CalDAV
    /// `…/principal/` URL of random characters. Such a participant still renders as a
    /// chip but is excluded from email recipients.
    public let emailAddress: String?

    public var displayName: String {
        name ?? emailAddress ?? url.absoluteString
    }

    public init(participant: EKParticipant) {
        name = participant.name
        url = participant.url
        role = Role(participant.participantRole)
        status = Status(participant.participantStatus)
        kind = Kind(participant.participantType)
        isCurrentUser = participant.isCurrentUser
        emailAddress = WBEventAttendee.extractedEmailAddress(
            name: name,
            url: url,
            kind: kind
        )
    }

    /// The valid email address carried by the participant's URL or name, or `nil`. Only
    /// people (and `.unknown`, which backends use for real invitees) warn on a miss —
    /// rooms and resources aren't recipients.
    private static func extractedEmailAddress(name: String?, url: URL, kind: Kind) -> String? {
        let candidate: String?
        if url.scheme?.lowercased() == "mailto" {
            candidate = String(url.absoluteString.dropFirst("mailto:".count))
                .components(separatedBy: "?")
                .first
        } else if let name, name.contains("@") {
            candidate = name
        } else {
            candidate = nil
        }
        guard let candidate, isValidEmailAddress(candidate) else {
            if kind == .person || kind == .unknown {
                WBLog.warning(
                    "Participant '\(name ?? "?")' has no valid email address (URL '\(url.absoluteString)') — excluded from email recipients"
                )
            }
            return nil
        }
        return candidate
    }

    /// One non-space local part, an `@`, and a dotted non-space domain — deliberately
    /// loose, just enough to reject principal paths and other non-address junk.
    private static func isValidEmailAddress(_ address: String) -> Bool {
        address.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
            options: .regularExpression
        ) != nil
    }
}

public extension WBEventAttendee {
    /// The display list of people for an event: the organizer first, then the attendees.
    ///
    /// Keeps `.person` participants **and `.unknown` ones** — many calendar backends report
    /// real invitees with an unknown participant type, so filtering to `.person` alone drops
    /// them (rooms/resources/groups are still excluded). De-duplicates: two entries are the
    /// same person if they share a `url` **or** a case-insensitive, trimmed name. Order is
    /// preserved (organizer first, then attendees as given).
    static func personList(
        organizer: WBEventAttendee?,
        attendees: [WBEventAttendee]
    ) -> [WBEventAttendee] {
        let combined = ([organizer].compactMap { $0 }) + attendees
        var result: [WBEventAttendee] = []
        for person in combined where person.kind == .person || person.kind == .unknown {
            let alreadyAdded = result.contains { existing in
                if existing.url == person.url {
                    return true
                }
                guard namesMatch(existing.name, person.name) else {
                    return false
                }
                // A shared display name is still two people when it carries two different
                // addresses (e.g. one person invited on two accounts) — never collapse
                // distinct emails into one entry.
                if let existingEmail = existing.emailAddress,
                   let personEmail = person.emailAddress,
                   existingEmail.caseInsensitiveCompare(personEmail) != .orderedSame {
                    return false
                }
                return true
            }
            if !alreadyAdded {
                result.append(person)
            }
        }
        return result
    }

    private static func namesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return left.caseInsensitiveCompare(right) == .orderedSame
    }
}
