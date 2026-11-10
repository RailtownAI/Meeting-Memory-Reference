import SwiftUI
import WhiteboardCore

/// Result of the save pipeline: a status card (spinner / success / failure) on top, the linked
/// meeting at the bottom. Pushed from the review screen; it performs the save on appear.
/// `onFinish` dismisses the whole capture flow back to Home.
struct WBiOSSaveResultView: View {
    @State private var viewModel: WBiOSSaveResultViewModel
    let onFinish: () -> Void
    /// Fired once the record is ingested into railengine so Home can refresh.
    let onSaved: () -> Void

    init(
        image: UIImage,
        title: String,
        summary: String,
        ocrText: String,
        actionItems: [String],
        meeting: WBiOSMeeting,
        onFinish: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: WBiOSSaveResultViewModel(
            image: image,
            title: title,
            summary: summary,
            ocrText: ocrText,
            actionItemTexts: actionItems,
            meeting: meeting
        ))
        self.onFinish = onFinish
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: .spacing4XL) {
            statusCard
            Spacer()
            linkedToSection
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(leftButtonTitle) {
                    onFinish()
                }
                .tint(Color.plainButtonText)
            }
            if isFailed {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Retry") {
                        Task {
                            await viewModel.save()
                            notifyIfPersisted()
                        }
                    }
                    .tint(Color.plainButtonText)
                }
            }
        }
        .task {
            await viewModel.save()
            notifyIfPersisted()
        }
    }

    /// Tells Home to refresh its captures once the record is in railengine, so the new row appears.
    /// Loading/failure don't refresh.
    private func notifyIfPersisted() {
        switch viewModel.state {
        case .saved:
            onSaved()
        case .loading, .failed:
            break
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(spacing: .spacingXL) {
            statusImage
            Text(cardTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            if let subtitle = cardSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacing4XL)
        .padding(.horizontal, .spacingXL)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: .radiusLG))
    }

    @ViewBuilder
    private var statusImage: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(height: 64)
        case .saved:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Linked meeting

    private var linkedToSection: some View {
        VStack(alignment: .leading, spacing: .spacingSM) {
            Text("Linked to")
                .font(.headline)
            WBiOSMeetingRowView(meeting: viewModel.meeting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - State-derived text

    private var cardTitle: String {
        switch viewModel.state {
        case .loading:
            return "Processing..."
        case .saved:
            return "Whiteboard saved to Meeting Memory"
        case .failed:
            return "Whiteboard failed to save to Meeting Memory"
        }
    }

    private var cardSubtitle: String? {
        if case .saved = viewModel.state {
            return "Synced to Railengine"
        }
        return nil
    }

    private var leftButtonTitle: String {
        switch viewModel.state {
        case .saved:
            return "Done"
        case .loading, .failed:
            return "Cancel"
        }
    }

    private var isFailed: Bool {
        if case .failed = viewModel.state {
            return true
        }
        return false
    }
}
