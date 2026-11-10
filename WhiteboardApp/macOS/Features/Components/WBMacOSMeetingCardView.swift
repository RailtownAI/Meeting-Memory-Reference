import SwiftUI

/// Card row for a meeting: calendar icon, title, and time. Used by the Home column's
/// Related Meetings list and the whiteboard detail's meeting header. Shows a time range
/// when `endDate` is given, and an optional trailing chevron for navigable cards.
struct WBMacOSMeetingCardView: View {
    let title: String
    let startDate: Date
    var endDate: Date?
    var showsChevron = false
    var isSelected = false

    var body: some View {
        HStack(spacing: .spacingXL) {
            Image(systemName: "calendar")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(.quinary, in: RoundedRectangle(cornerRadius: .radiusSM))
            VStack(alignment: .leading, spacing: .spacingXXS) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(timeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.spacingXL)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: .radiusMD))
        .overlay {
            RoundedRectangle(cornerRadius: .radiusMD)
                .strokeBorder(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
    }

    private var timeText: String {
        guard let endDate else {
            return startDate.wbMacOSCapturedAtText
        }
        return startDate.wbMacOSCapturedAtText
            + " – "
            + endDate.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    VStack {
        WBMacOSMeetingCardView(title: "Apple Demo", startDate: .now)
        WBMacOSMeetingCardView(
            title: "Apple Demo",
            startDate: .now,
            endDate: .now.addingTimeInterval(3_600),
            showsChevron: true
        )
    }
    .padding()
}
