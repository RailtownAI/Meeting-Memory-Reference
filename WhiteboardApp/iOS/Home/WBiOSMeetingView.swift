import SwiftUI

/// Meeting detail subview: meeting info (section A) stacked above the attendees list (section B),
/// separated by `.spacingXL`.
struct WBiOSMeetingView: View {
    let title: String
    /// Preformatted time range with date, e.g. "11:00AM - 12:00PM (Jul 31, 2026)".
    let timeRange: String
    let location: String?
    let attendees: [WBiOSAttendee]

    /// How many attendees show individually before collapsing the rest into a "+n".
    private let maxVisibleAttendees = 3

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXL) {
            infoSection
            if !attendees.isEmpty {
                attendeesSection
            }
        }
    }

    // MARK: - Section A — meeting info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(timeRange)
                .font(.subheadline)
            if let location, !location.isEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Section B — attendees

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: .spacingMD) {
            Text("Attendees")
                .font(.headline)

            HStack(spacing: .spacingXL) {
                ForEach(attendees.prefix(maxVisibleAttendees)) { attendee in
                    WBiOSAttendeeView(attendee: attendee)
                }
                if attendees.count > maxVisibleAttendees {
                    Text("+\(attendees.count - maxVisibleAttendees)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    WBiOSMeetingView(
        title: "Architecture Discussion",
        timeRange: "11:00AM - 12:00PM",
        location: "Conference Room A",
        attendees: [
            WBiOSAttendee(id: "1", name: "Jane"),
            WBiOSAttendee(id: "2", name: "Mark"),
            WBiOSAttendee(id: "3", name: "Sffair"),
            WBiOSAttendee(id: "4", name: "Alex"),
            WBiOSAttendee(id: "5", name: "Sam")
        ]
    )
    .padding()
}
