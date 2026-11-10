import SwiftUI

/// Home tab — a meeting summary above the persistent "Capture Whiteboard" button, in a scroll view.
struct WBiOSHomeView: View {
    @State private var viewModel = WBiOSHomeViewModel()
    @State private var meetingViewModel = WBiOSMeetingViewModel()
    @State private var captureModel = WBiOSImageCaptureModel()
    @State private var isMeetingPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacing5XL) {
                    meetingRow
                    captureButton
                    if meetingViewModel.selectedID != nil {
                        capturesSection
                    }
                }
                .padding(.top, .spacing5XL)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                await meetingViewModel.load(source: "refreshable", force: true)
            }
            .task {
                await meetingViewModel.load(source: "task")
            }
            .sheet(isPresented: $isMeetingPickerPresented) {
                WBiOSMeetingPickerView(
                    meetings: meetingViewModel.meetings,
                    selectedID: meetingViewModel.selectedID
                ) { meeting in
                    meetingViewModel.select(meeting)
                }
            }
            .navigationTitle("Meeting")
            .fullScreenCover(isPresented: Binding(
                get: { viewModel.capturedImage != nil },
                set: { presented in
                    if !presented {
                        viewModel.capturedImage = nil
                    }
                }
            )) {
                if let image = viewModel.capturedImage,
                   let selectedID = meetingViewModel.selectedID {
                    WBiOSImageReviewView(
                        image: image,
                        meetings: meetingViewModel.meetings,
                        selectedMeetingID: selectedID,
                        onSaved: { meetingViewModel.refreshCaptures() }
                    )
                }
            }
        }
    }

    private var meetingRow: some View {
        HStack(alignment: .top, spacing: .spacingMD) {
            meetingSection
            Spacer()
            calendarButton
        }
        .padding(.horizontal, .spacing4XL)
    }

    @ViewBuilder
    private var meetingSection: some View {
        switch meetingViewModel.state {
        case .loading:
            ProgressView()
        case .loaded(let meeting):
            WBiOSMeetingView(
                title: meeting.title,
                timeRange: meeting.timeRangeText,
                location: meeting.location,
                attendees: meeting.attendees
            )
        case .empty:
            Text("No meeting found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .accessDenied:
            VStack(alignment: .leading, spacing: .spacingMD) {
                Text("Calendar permission is needed to load your latest meeting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    meetingViewModel.openSettings()
                }
            }
        }
    }

    /// Opens the meeting picker so the user can swap the auto-detected meeting for another cached one.
    private var calendarButton: some View {
        Button {
            isMeetingPickerPresented = true
        } label: {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(Color.accentButtonBackground)
                .frame(width: .buttonHeightMD, height: .buttonHeightMD)
                .background(Color.accentButtonBackground.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: .radiusMD))
        }
        .buttonStyle(.plain)
        .disabled(meetingViewModel.meetings.isEmpty)
        .accessibilityLabel("Select a different meeting")
    }

    private var captureButton: some View {
        Button {
            captureModel.start()
        } label: {
            Label("Capture Whiteboard", systemImage: "camera")
                .font(.headline)
                .foregroundStyle(Color.accentButtonText)
                .frame(maxWidth: .infinity)
                .frame(height: .buttonHeightLG)
                .background(Color.accentButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: .radiusMD))
        }
        .buttonStyle(.plain)
        .imageCapture(captureModel) { image in
            viewModel.capturedImage = image
        }
        .disabled(meetingViewModel.selectedID == nil)
        .opacity(meetingViewModel.selectedID == nil ? 0.5 : 1)
        .padding(.horizontal, .spacing4XL)
    }

    private var capturesSection: some View {
        VStack(alignment: .leading, spacing: .spacingMD) {
            Text("Recent Captures")
                .font(.headline)
            capturesContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, .spacing4XL)
    }

    @ViewBuilder
    private var capturesContent: some View {
        switch meetingViewModel.capturesState {
        case .loading:
            ProgressView()
        case .iCloudUnavailable:
            Text("iCloud is unavailable. Sign in to iCloud to see recent captures.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .loaded(let captures):
            if captures.isEmpty {
                Text("No recent captures")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: .spacingMD) {
                    ForEach(captures) { capture in
                        WBiOSCaptureRow(capture: capture) { imageID in
                            await meetingViewModel.captureImage(imageID: imageID)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    WBiOSHomeView()
}
