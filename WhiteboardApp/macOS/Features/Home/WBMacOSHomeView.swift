import SwiftUI

/// Column 2: the question, the agent's answer, and the whiteboards the answer references.
struct WBMacOSHomeView: View {
    
    @State private var viewModel: WBMacOSHomeViewModel

    @FocusState private var isSearchFocused: Bool

    init(
        imageProvider: WBMacOSWhiteboardImageProviding,
        manager: WBMacOSSelectionManager,
        sessionManager: WBMacOSAnswerSessionManager
    ) {
        _viewModel = State(
            initialValue: WBMacOSHomeViewModel(
                imageProvider: imageProvider,
                manager: manager,
                sessionManager: sessionManager
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, .spacing4XL)
                .padding(.top, .spacing3XL)
            mainContent
        }
        .navigationTitle("Home")
    }

    private var searchField: some View {
        HStack(spacing: .spacingMD) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("What did we discuss about Railengine?", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.submitSearch()
                }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverOpacity()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, .spacingXL)
        .padding(.vertical, .spacingMD)
        .background(.quinary, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor, lineWidth: isSearchFocused ? 2 : 0)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.answerState {
            case .idle:
                ContentUnavailableView(
                    "Ask about your meetings",
                    systemImage: "sparkles",
                    description: Text("Search above to get an answer drawn from your whiteboards.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: .spacing6XL) {
                        answerSection
                        whiteboardsSection
                        relatedMeetingsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.spacing4XL)
                }
        }
    }

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: .spacingXL) {
            sectionHeaderView(for: "Answer")
            answerBody
        }
    }

    @ViewBuilder
    private var answerBody: some View {
        switch viewModel.answerState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: .spacingMD) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching your meetings…")
                    .foregroundStyle(.secondary)
            }
        case .loaded(let answer):
            Text(answer.text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't answer that",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    @ViewBuilder
    private var whiteboardsSection: some View {
        if !viewModel.whiteboards.isEmpty {
            VStack(alignment: .leading, spacing: .spacingXL) {
                sectionHeaderView(for: "Referenced Whiteboards")
                ScrollView(.horizontal) {
                    HStack(spacing: .spacing3XL) {
                        ForEach(viewModel.whiteboards) { whiteboard in
                            Button {
                                viewModel.selectWhiteboard(whiteboard)
                            } label: {
                                whiteboardThumbnail(
                                    for: whiteboard,
                                    isSelected: whiteboard.id == viewModel.selectedWhiteboardID
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverOpacity()
                        }
                    }
                    .padding(.vertical, .spacingXS)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
    
    @ViewBuilder
    private var relatedMeetingsSection: some View {
        if !viewModel.relatedMeetings.isEmpty {
            VStack(alignment: .leading, spacing: .spacingXL) {
                sectionHeaderView(for: "Related Meetings")
                VStack(spacing: .spacingMD) {
                    ForEach(viewModel.relatedMeetings) { meeting in
                        Button {
                            viewModel.selectRelatedMeeting(meeting)
                        } label: {
                            WBMacOSMeetingCardView(
                                title: meeting.title,
                                startDate: meeting.startDate,
                                isSelected: meeting.id == viewModel.selectedRelatedMeetingID
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverOpacity()
                    }
                }
            }
        }
    }

    private func sectionHeaderView(for title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
    
    private func whiteboardThumbnail(for whiteboard: WBMacOSWhiteboard, isSelected: Bool) -> some View {
        WBMacOSWhiteboardImageView(
            imageID: whiteboard.imageID,
            cornerRadius: .radiusSM,
            imageProvider: viewModel.imageProvider
        )
        .frame(
            width: 132,
            height: 92
        )
        .overlay {
            RoundedRectangle(cornerRadius: .radiusSM)
                .strokeBorder(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
        // The image letterboxes inside the fixed frame; without an explicit content shape
        // the transparent gaps would not be clickable or hoverable.
        .contentShape(RoundedRectangle(cornerRadius: .radiusSM))
    }
}
