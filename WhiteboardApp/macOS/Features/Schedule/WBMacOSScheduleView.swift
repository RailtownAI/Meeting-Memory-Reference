import SwiftUI

/// Schedule column (Today, This Week): the calendar events in the scope's window. Opening
/// one shows its meeting's captures in the detail column.
struct WBMacOSScheduleView: View {

    @State private var viewModel: WBMacOSScheduleViewModel

    init(
        scope: WBMacOSScheduleScope,
        scheduleEventsProvider: WBMacOSScheduleEventsProviding,
        eventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding,
        attendeeImageProvider: WBMacOSAttendeeImageProviding,
        manager: WBMacOSSelectionManager
    ) {
        _viewModel = State(
            initialValue: WBMacOSScheduleViewModel(
                scope: scope,
                scheduleEventsProvider: scheduleEventsProvider,
                eventWhiteboardsProvider: eventWhiteboardsProvider,
                attendeeImageProvider: attendeeImageProvider,
                manager: manager
            )
        )
    }

    private static let inlineAttendeeCount = 3

    var body: some View {
        Group {
            switch viewModel.eventsState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let events):
                if events.isEmpty {
                    ContentUnavailableView(
                        viewModel.scope.emptyStateTitle,
                        systemImage: "calendar",
                        description: Text(viewModel.scope.emptyStateDescription)
                    )
                } else {
                    eventList(events)
                }
            case .failed(let message):
                ContentUnavailableView(
                    "Couldn't load \(viewModel.scope.title.lowercased())",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle(viewModel.scope.title)
        .task {
            await viewModel.load()
        }
    }

    private func eventList(_ events: [WBMacOSScheduleEvent]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .spacing4XL) {
                ForEach(events) { event in
                    Button {
                        viewModel.openEvent(event)
                    } label: {
                        eventCard(for: event)
                    }
                    .buttonStyle(.plain)
                    .hoverOpacity()
                    if event.id != events.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.spacing4XL)
        }
    }

    private func eventCard(for event: WBMacOSScheduleEvent) -> some View {
        let isSelected = viewModel.selectedEventID == event.id
        return VStack(alignment: .leading, spacing: .spacingMD) {
            Text(event.title)
                .font(.title3.weight(.semibold))
            Text(timeText(for: event))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let location = event.location {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !event.attendees.isEmpty {
                VStack(alignment: .leading, spacing: .spacingMD) {
                    Text("Attendees")
                        .font(.footnote.weight(.semibold))
                    attendeeRow(for: event)
                }
                .padding(.top, .spacingXS)
            }
        }
        // Full-width frame + explicit content shape make the whole row clickable and
        // hoverable, not just the text.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: .radiusSM))
        // Selection ring drawn outside the row's content (inner padding cancelled by the
        // negative outer padding), so unselected rows keep the flat layout untouched.
        .padding(.spacingLG)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: .radiusMD)
                    .fill(Color.accentColor.opacity(0.08))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: .radiusMD)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .padding(-.spacingLG)
    }

    /// "6:00 PM – 7:00 PM" — prefixed with the weekday ("Wednesday, …") when the scope
    /// spans more than a day.
    private func timeText(for event: WBMacOSScheduleEvent) -> String {
        let times = event.startDate.formatted(date: .omitted, time: .shortened)
            + " – "
            + event.endDate.formatted(date: .omitted, time: .shortened)
        guard viewModel.scope.showsWeekday else {
            return times
        }
        return event.startDate.formatted(.dateTime.weekday(.wide)) + ", " + times
    }

    private func attendeeRow(for event: WBMacOSScheduleEvent) -> some View {
        HStack(spacing: .spacingXL) {
            ForEach(event.attendees.prefix(WBMacOSScheduleView.inlineAttendeeCount)) { attendee in
                WBMacOSAttendeeChipView(
                    attendee: attendee,
                    imageProvider: viewModel.attendeeImageProvider
                )
            }
            if event.attendees.count > WBMacOSScheduleView.inlineAttendeeCount {
                Text("+\(event.attendees.count - WBMacOSScheduleView.inlineAttendeeCount)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, .spacingMD)
                    .padding(.vertical, .spacingXXS)
                    .background(.quinary, in: Capsule())
            }
        }
    }
}
