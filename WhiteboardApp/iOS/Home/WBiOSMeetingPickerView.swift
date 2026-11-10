import SwiftUI

/// A picker for choosing which cached meeting the Home screen shows, in place of the auto-detected
/// one. Each row reuses `WBiOSMeetingView`; tapping a row selects it and dismisses.
struct WBiOSMeetingPickerView: View {
    let meetings: [WBiOSMeeting]
    /// `id` of the meeting currently shown on Home — its row is highlighted.
    let selectedID: String?
    let onSelect: (WBiOSMeeting) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(meetings) { meeting in
                Button {
                    onSelect(meeting)
                    dismiss()
                } label: {
                    WBiOSMeetingView(
                        title: meeting.title,
                        timeRange: meeting.timeRangeText,
                        location: meeting.location,
                        attendees: meeting.attendees
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(meeting.id == selectedID ? Color.selectedRowBackground : nil)
            }
            .navigationTitle("Select Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
