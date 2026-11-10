import CoreLocation
import EventKit

/// Value snapshot of an `EKEvent` carrying every detail EventKit exposes, so events can be
/// listed, displayed, and referenced without holding live EventKit objects.
public struct WBCalendarEvent: Identifiable, Sendable {
    public enum Status: String, Sendable {
        case none, confirmed, tentative, canceled

        init(_ status: EKEventStatus) {
            switch status {
            case .confirmed: self = .confirmed
            case .tentative: self = .tentative
            case .canceled: self = .canceled
            case .none: self = .none
            @unknown default: self = .none
            }
        }
    }

    public enum Availability: String, Sendable {
        case notSupported, busy, free, tentative, unavailable

        init(_ availability: EKEventAvailability) {
            switch availability {
            case .busy: self = .busy
            case .free: self = .free
            case .tentative: self = .tentative
            case .unavailable: self = .unavailable
            case .notSupported: self = .notSupported
            @unknown default: self = .notSupported
            }
        }
    }

    public struct CalendarInfo: Identifiable, Sendable {
        /// The kind of calendar an event lives on — used to filter out non-meeting sources
        /// (`.birthday`, `.subscription` — e.g. Holidays).
        public enum CalendarType: String, Sendable {
            case local, calDAV, exchange, subscription, birthday, unknown

            init(_ type: EKCalendarType) {
                switch type {
                case .local: self = .local
                case .calDAV: self = .calDAV
                case .exchange: self = .exchange
                case .subscription: self = .subscription
                case .birthday: self = .birthday
                @unknown default: self = .unknown
                }
            }
        }

        /// `EKCalendar.calendarIdentifier` — usable to scope event fetches to specific calendars.
        public let identifier: String
        public let title: String
        public let sourceTitle: String
        public let allowsModifications: Bool
        public let type: CalendarType

        public var id: String { identifier }

        public init(calendar: EKCalendar) {
            identifier = calendar.calendarIdentifier
            title = calendar.title
            sourceTitle = calendar.source.title
            allowsModifications = calendar.allowsContentModifications
            type = CalendarType(calendar.type)
        }
    }

    public struct StructuredLocation: Sendable {
        public let title: String?
        public let coordinate: CLLocationCoordinate2D?
        public let radiusMeters: Double?
    }

    public struct Alarm: Sendable {
        /// Offset from the event start (negative = before), when the alarm is relative.
        public let relativeOffset: TimeInterval?
        /// Fixed fire date, when the alarm is absolute.
        public let absoluteDate: Date?
    }

    /// Device-local identifier. Not stable across devices — use `externalIdentifier` for that.
    public let eventIdentifier: String?
    public let calendarItemIdentifier: String
    /// `calendarItemExternalIdentifier` — stable across devices and calendar databases.
    public let externalIdentifier: String?

    public let title: String
    public let notes: String?
    public let location: String?
    public let structuredLocation: StructuredLocation?
    public let url: URL?

    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let timeZone: TimeZone?

    public let calendar: CalendarInfo?
    public let organizer: WBEventAttendee?
    public let attendees: [WBEventAttendee]

    public let status: Status
    public let availability: Availability

    /// True when this is a modified occurrence of a recurring event.
    public let isDetached: Bool
    public let occurrenceDate: Date?
    public let hasRecurrenceRules: Bool
    public let recurrenceRuleDescriptions: [String]

    public let alarms: [Alarm]
    public let creationDate: Date?
    public let lastModifiedDate: Date?
    public let birthdayContactIdentifier: String?

    public var id: String { calendarItemIdentifier }

    public init(event: EKEvent) {
        eventIdentifier = event.eventIdentifier
        calendarItemIdentifier = event.calendarItemIdentifier
        externalIdentifier = event.calendarItemExternalIdentifier
        title = event.title ?? "(untitled)"
        notes = event.notes
        location = event.location
        structuredLocation = event.structuredLocation.map { location in
            StructuredLocation(
                title: location.title,
                coordinate: location.geoLocation?.coordinate,
                radiusMeters: location.radius > 0 ? location.radius : nil
            )
        }
        url = event.url
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        timeZone = event.timeZone
        calendar = event.calendar.map(CalendarInfo.init)
        organizer = event.organizer.map(WBEventAttendee.init)
        attendees = (event.attendees ?? []).map(WBEventAttendee.init)
        status = Status(event.status)
        availability = Availability(event.availability)
        isDetached = event.isDetached
        occurrenceDate = event.occurrenceDate
        hasRecurrenceRules = event.hasRecurrenceRules
        recurrenceRuleDescriptions = (event.recurrenceRules ?? []).map { String(describing: $0) }
        alarms = (event.alarms ?? []).map { alarm in
            Alarm(
                relativeOffset: alarm.absoluteDate == nil ? alarm.relativeOffset : nil,
                absoluteDate: alarm.absoluteDate
            )
        }
        creationDate = event.creationDate
        lastModifiedDate = event.lastModifiedDate
        birthdayContactIdentifier = event.birthdayContactIdentifier
    }
}
