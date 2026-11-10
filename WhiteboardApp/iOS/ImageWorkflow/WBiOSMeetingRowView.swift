import SwiftUI

/// A meeting shown as a bordered row: a multicolor calendar icon, the title + day/time, an
/// optional trailing chevron, and the meeting's attendees below (when it has any). Pass
/// `onTap` to make it a button (with chevron) for reassigning the meeting; omit it for a
/// static, non-interactive row (no chevron).
struct WBiOSMeetingRowView: View {
    let meeting: WBiOSMeeting
    var onTap: (() -> Void)?

    /// How many attendees show individually before collapsing the rest into a "+n".
    private let maxVisibleAttendees = 3

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                rowContent(showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(showsChevron: false)
        }
    }

    private func rowContent(showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: .spacingMD) {
                Image(systemName: "calendar")
                    .symbolRenderingMode(.multicolor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: .spacingXXS) {
                    Text(meeting.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(meeting.dayTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 60)
            if !meeting.attendees.isEmpty {
                attendeeRow
                    .padding(.bottom, .spacingMD)
            }
        }
        .padding(.horizontal, .spacingMD)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: .radiusMD)
                .stroke(Color(.separator), lineWidth: 1)
        }
    }

    private var attendeeRow: some View {
        HStack(spacing: .spacingXL) {
            ForEach(meeting.attendees.prefix(maxVisibleAttendees)) { attendee in
                WBiOSAttendeeView(attendee: attendee)
            }
            if meeting.attendees.count > maxVisibleAttendees {
                Text("+\(meeting.attendees.count - maxVisibleAttendees)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
