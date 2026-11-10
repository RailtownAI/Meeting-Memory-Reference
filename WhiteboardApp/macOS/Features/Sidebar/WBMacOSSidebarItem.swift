/// Every destination in the sidebar. Only `.home` is implemented on this branch; the rest
/// render placeholders until their issues land.
enum WBMacOSSidebarItem: String, CaseIterable, Identifiable {
    case home
    case today
    case thisWeek
    case allMeetings
    case meetings
    case whiteboards
    case actionItems
    case people
    case withMark
    case needsFollowUp
    case architecture
    case railengine

    enum Section {
        case primary
        case browse
        case smartLists
    }

    static func items(in section: Section) -> [WBMacOSSidebarItem] {
        allCases.filter { $0.section == section }
    }

    var id: String {
        rawValue
    }

    var section: Section {
        switch self {
        case .home, .today, .thisWeek, .allMeetings:
            return .primary
        case .meetings, .whiteboards, .actionItems, .people:
            return .browse
        case .withMark, .needsFollowUp, .architecture, .railengine:
            return .smartLists
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .allMeetings: return "All Meetings"
        case .meetings: return "Meetings"
        case .whiteboards: return "Whiteboards"
        case .actionItems: return "Action Items"
        case .people: return "People"
        case .withMark: return "With Mark"
        case .needsFollowUp: return "Needs Follow Up"
        case .architecture: return "Architecture"
        case .railengine: return "Railengine"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .today: return "calendar"
        case .thisWeek: return "calendar.badge.clock"
        case .allMeetings: return "tray.full"
        case .meetings: return "person.2"
        case .whiteboards: return "rectangle.on.rectangle"
        case .actionItems: return "checklist"
        case .people: return "person.crop.circle"
        case .withMark: return "person.crop.circle.badge.checkmark"
        case .needsFollowUp: return "flag"
        case .architecture: return "square.grid.3x3"
        case .railengine: return "cpu"
        }
    }
}
