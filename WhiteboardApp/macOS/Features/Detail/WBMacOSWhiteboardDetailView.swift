import SwiftUI

/// Column 3: the selected whiteboard — its meeting, title, photo carousel, a Summary /
/// OCR Text / Details segmented view, and the meeting's attendees.
struct WBMacOSWhiteboardDetailView: View {

    @Environment(\.openURL) private var openURL

    @State private var viewModel: WBMacOSWhiteboardDetailViewModel

    init(
        imageProvider: WBMacOSWhiteboardImageProviding,
        attendeeImageProvider: WBMacOSAttendeeImageProviding,
        actionItemsProvider: WBMacOSActionItemsProviding,
        manager: WBMacOSSelectionManager,
        sessionManager: WBMacOSAnswerSessionManager,
        meetingDetailManager: WBMacOSMeetingDetailManager
    ) {
        _viewModel = State(
            initialValue: WBMacOSWhiteboardDetailViewModel(
                imageProvider: imageProvider,
                attendeeImageProvider: attendeeImageProvider,
                actionItemsProvider: actionItemsProvider,
                manager: manager,
                sessionManager: sessionManager,
                meetingDetailManager: meetingDetailManager
            )
        )
    }

    private static let imageCornerRadius: CGFloat = .radiusMD
    private static let imageHeight: CGFloat = 420
    private static let inlineAttendeeCount = 3

    var body: some View {
        detailStates
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .task(id: viewModel.whiteboard?.id) {
                await viewModel.whiteboardDidChange()
            }
    }

    /// No close affordance here — dismissal is by deselection: clicking the selected item
    /// again (Home thumbnail, related meeting, Today event) or switching destinations.
    @ViewBuilder
    private var detailStates: some View {
        if let whiteboard = viewModel.displayedWhiteboard {
            content(for: whiteboard)
        } else if viewModel.isDetailLoading {
            ProgressView()
                .controlSize(.large)
        } else if viewModel.isDetailEmpty {
            ContentUnavailableView(
                "No whiteboards",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("No captures were found for this meeting.")
            )
        } else {
            ContentUnavailableView(
                "No whiteboard selected",
                systemImage: "rectangle.on.rectangle",
                description: Text("Pick a whiteboard to see its summary.")
            )
        }
    }

    private func content(for whiteboard: WBMacOSWhiteboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .spacing3XL) {
                meetingSection

                VStack(alignment: .leading, spacing: .spacingXS) {
                    Text(whiteboard.title)
                        .font(.title2.weight(.semibold))
                    Text(
                        whiteboard.capturedAt.wbMacOSSubtitle(
                            meetingTitle: viewModel.meetingDetail?.title
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                imageCarousel

                Picker("Section", selection: $viewModel.selectedSegment) {
                    ForEach(WBMacOSWhiteboardDetailViewModel.Segment.allCases) { segment in
                        Text(segment.rawValue)
                            .tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                segmentContent(for: whiteboard)

                WBMacOSActionItemsSectionView(
                    whiteboard: whiteboard,
                    actionItemsProvider: viewModel.actionItemsProvider,
                    onItemsChanged: { items in
                        viewModel.actionItemsDidChange(items, forWhiteboardID: whiteboard.id)
                    }
                )

                attendeesSection

                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.spacing4XL)
        }
    }

    @ViewBuilder
    private var meetingSection: some View {
        if let meetingDetail = viewModel.meetingDetail {
            VStack(alignment: .leading, spacing: .spacingXL) {
                Text("Meeting")
                    .font(.headline)
                WBMacOSMeetingCardView(
                    title: meetingDetail.title,
                    startDate: meetingDetail.startDate,
                    endDate: meetingDetail.endDate,
                    showsChevron: true
                )
            }
        }
    }

    /// Pages the meeting's captures — one whiteboard record per photo, matching the
    /// railengine contract. The sections below follow the visible page.
    @ViewBuilder
    private var imageCarousel: some View {
        let pages = viewModel.meetingWhiteboards
        if pages.count <= 1 {
            WBMacOSWhiteboardImageView(
                imageID: pages.first?.imageID,
                cornerRadius: WBMacOSWhiteboardDetailView.imageCornerRadius,
                imageProvider: viewModel.imageProvider
            )
            .frame(maxWidth: .infinity)
            .frame(height: WBMacOSWhiteboardDetailView.imageHeight)
        } else {
            VStack(spacing: .spacingMD) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages) { page in
                            WBMacOSWhiteboardImageView(
                                imageID: page.imageID,
                                cornerRadius: WBMacOSWhiteboardDetailView.imageCornerRadius,
                                imageProvider: viewModel.imageProvider
                            )
                            .frame(maxHeight: WBMacOSWhiteboardDetailView.imageHeight)
                            .containerRelativeFrame(.horizontal)
                            .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(height: WBMacOSWhiteboardDetailView.imageHeight)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $viewModel.visibleWhiteboardID)
                .scrollIndicators(.hidden)
                carouselDots(for: pages)
            }
        }
    }

    private func carouselDots(for pages: [WBMacOSWhiteboard]) -> some View {
        HStack(spacing: .spacingSM) {
            ForEach(pages) { page in
                let isVisible = page.id == (viewModel.visibleWhiteboardID ?? pages.first?.id)
                Circle()
                    .fill(isVisible ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func segmentContent(for whiteboard: WBMacOSWhiteboard) -> some View {
        switch viewModel.selectedSegment {
        case .summary:
            Text(whiteboard.summary)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .ocrText:
            Text(whiteboard.ocrText)
                .font(.body.monospaced())
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .details:
            detailRows(for: whiteboard)
        }
    }

    private func detailRows(for whiteboard: WBMacOSWhiteboard) -> some View {
        VStack(alignment: .leading, spacing: .spacingMD) {
            LabeledContent("Captured", value: whiteboard.capturedAt.wbMacOSCapturedAtText)
            LabeledContent("Meeting", value: viewModel.meetingDetail?.title ?? "—")
            LabeledContent("Calendar event", value: whiteboard.calendarEventID ?? "—")
            LabeledContent("Image", value: whiteboard.imageID ?? "—")
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var attendeesSection: some View {
        if let meetingDetail = viewModel.meetingDetail, !meetingDetail.attendees.isEmpty {
            VStack(alignment: .leading, spacing: .spacingXL) {
                Text("Attendees")
                    .font(.headline)
                HStack(spacing: .spacingXL) {
                    ForEach(
                        meetingDetail.attendees.prefix(WBMacOSWhiteboardDetailView.inlineAttendeeCount)
                    ) { attendee in
                        WBMacOSAttendeeChipView(
                            attendee: attendee,
                            imageProvider: viewModel.attendeeImageProvider
                        )
                    }
                    if meetingDetail.attendees.count > WBMacOSWhiteboardDetailView.inlineAttendeeCount {
                        remainingAttendeesButton(for: meetingDetail)
                    }
                }
            }
        }
    }

    private func remainingAttendeesButton(for meetingDetail: WBMacOSMeetingDetail) -> some View {
        Button {
            viewModel.isAttendeesPopoverShown = true
        } label: {
            Text("+\(meetingDetail.attendees.count - WBMacOSWhiteboardDetailView.inlineAttendeeCount)")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, .spacingMD)
                .padding(.vertical, .spacingXS)
                .background(.quinary, in: Capsule())
        }
        .buttonStyle(.plain)
        .hoverOpacity()
        .popover(isPresented: $viewModel.isAttendeesPopoverShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: .spacingXL) {
                ForEach(
                    Array(meetingDetail.attendees.dropFirst(WBMacOSWhiteboardDetailView.inlineAttendeeCount))
                ) { attendee in
                    WBMacOSAttendeeChipView(
                        attendee: attendee,
                        imageProvider: viewModel.attendeeImageProvider
                    )
                }
            }
            .padding(.spacing3XL)
        }
    }

    /// Email opens a draft in the default mail client — attendees as recipients, the shown
    /// whiteboard's title and summary as subject and body. Summary is still a stub.
    private var actionButtons: some View {
        HStack(spacing: .spacingXL) {
            Button("Summary", systemImage: "doc.text") {
            }
            .buttonStyle(.borderedProminent)
            .hoverOpacity()
            Button("Email", systemImage: "envelope") {
                if let emailURL = viewModel.emailURL {
                    openURL(emailURL)
                }
            }
            .buttonStyle(.bordered)
            .hoverOpacity()
            .disabled(viewModel.emailURL == nil)
        }
        .controlSize(.large)
    }

}
