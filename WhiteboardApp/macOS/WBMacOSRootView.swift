import SwiftUI

/// Root of the macOS app: sidebar → Home content → whiteboard detail. Holds only its own
/// view model; each column builds its own view model from the dependencies it is handed.
struct WBMacOSRootView: View {

    @State private var viewModel: WBMacOSRootViewModel

    init(
        manager: WBMacOSSelectionManager,
        sessionManager: WBMacOSAnswerSessionManager,
        meetingDetailManager: WBMacOSMeetingDetailManager,
        imageProvider: WBMacOSWhiteboardImageProviding,
        attendeeImageProvider: WBMacOSAttendeeImageProviding,
        actionItemsProvider: WBMacOSActionItemsProviding,
        scheduleEventsProvider: WBMacOSScheduleEventsProviding,
        eventWhiteboardsProvider: WBMacOSEventWhiteboardsProviding
    ) {
        _viewModel = State(
            initialValue: WBMacOSRootViewModel(
                manager: manager,
                sessionManager: sessionManager,
                meetingDetailManager: meetingDetailManager,
                imageProvider: imageProvider,
                attendeeImageProvider: attendeeImageProvider,
                actionItemsProvider: actionItemsProvider,
                scheduleEventsProvider: scheduleEventsProvider,
                eventWhiteboardsProvider: eventWhiteboardsProvider
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            WBMacOSSidebarView(manager: viewModel.manager)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 220)
        } detail: {
            // Inside the detail region, so dragging the inspector only ever competes with
            // the content column — outside the split view it squeezes the sidebar too. The
            // ZStack is the inspector's anchor: it stays alive across the Home ↔ Today
            // switch, whose identity change would otherwise tear the anchor out of AppKit's
            // split-view hierarchy and crash constraint activation.
            ZStack {
                contentColumn
            }
            // Explicit floor — without it a fully-dragged inspector is free to crush the
            // content column past viability.
            .frame(minWidth: 380)
            .inspector(isPresented: $viewModel.isDetailPresented) {
                WBMacOSWhiteboardDetailView(
                    imageProvider: viewModel.imageProvider,
                    attendeeImageProvider: viewModel.attendeeImageProvider,
                    actionItemsProvider: viewModel.actionItemsProvider,
                    manager: viewModel.manager,
                    sessionManager: viewModel.sessionManager,
                    meetingDetailManager: viewModel.meetingDetailManager
                )
                // Bounded on both ends — unbounded, a drag past the available width loops
                // AppKit's constraint pass. In narrow windows AppKit clamps the drag before
                // the max, since the content column holds its 380 floor.
                .inspectorColumnWidth(min: 380, ideal: 480, max: 600)
            }
        }
        .frame(minWidth: 1080, minHeight: 620)
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch viewModel.destination {
        case .home:
            WBMacOSHomeView(
                imageProvider: viewModel.imageProvider,
                manager: viewModel.manager,
                sessionManager: viewModel.sessionManager
            )
        case .today:
            scheduleColumn(scope: .today)
        case .thisWeek:
            scheduleColumn(scope: .thisWeek)
        default:
            ContentUnavailableView(
                viewModel.destination.title,
                systemImage: viewModel.destination.systemImage,
                description: Text("This view is not built yet.")
            )
            .navigationTitle(viewModel.destination.title)
        }
    }

    /// One schedule view serves both calendar destinations — only the scope differs. The
    /// switch's distinct branches give each destination its own view identity, so the view
    /// model rebuilds with the right scope on tab switch.
    private func scheduleColumn(scope: WBMacOSScheduleScope) -> some View {
        WBMacOSScheduleView(
            scope: scope,
            scheduleEventsProvider: viewModel.scheduleEventsProvider,
            eventWhiteboardsProvider: viewModel.eventWhiteboardsProvider,
            attendeeImageProvider: viewModel.attendeeImageProvider,
            manager: viewModel.manager
        )
    }
}
