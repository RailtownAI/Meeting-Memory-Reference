import SwiftUI

/// Full-screen review of a freshly captured (or picked) image before saving. Presented from Home
/// once an image is available; the nav bar carries "Cancel" (left) and "Save" (right).
struct WBiOSImageReviewView: View {
    @State private var viewModel: WBiOSImageReviewViewModel
    @State private var captureModel = WBiOSImageCaptureModel()
    @State private var isMeetingPickerPresented = false
    @State private var isRetakeConfirmationPresented = false
    @State private var isActionItemPromptPresented = false

    /// Which row the action-item prompt is editing. `nil` means it's adding a new one.
    @State private var editingActionItemID: UUID?

    /// Which action-item row is swiped open, if any. Held here rather than per-row so opening one
    /// row closes the others.
    @State private var openActionItemRow: UUID?

    /// Text being typed into the action-item prompt, whether adding or editing. Lives here rather
    /// than on the view model because it's transient editing state — it only becomes model data once
    /// the user taps OK.
    @State private var draftActionItem = ""
    @State private var isShowingResult = false
    @Environment(\.dismiss) private var dismiss

    /// Forwarded to the result screen; fired when the capture is persisted so Home can refresh.
    let onSaved: () -> Void

    init(
        image: UIImage,
        meetings: [WBiOSMeeting],
        selectedMeetingID: String,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: WBiOSImageReviewViewModel(
            image: image,
            meetings: meetings,
            selectedMeetingID: selectedMeetingID
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacing4XL) {
                    Image(uiImage: viewModel.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            retakeButton
                        }

                    reviewSection(
                        title: "Title",
                        isLoading: viewModel.isTitleLoading,
                        content: viewModel.title,
                        isFailed: viewModel.didTitleFail,
                        loadingPlaceholder: "Generating title…",
                        errorPlaceholder: "Couldn't generate a title"
                    )
                    reviewSection(
                        title: "Summary",
                        isLoading: viewModel.isSummaryLoading,
                        content: viewModel.summary,
                        isFailed: viewModel.didSummaryFail,
                        loadingPlaceholder: "Generating summary…",
                        errorPlaceholder: "Couldn't generate a summary"
                    )
                    if viewModel.summarizeFailure != nil {
                        retrySummarizeButton
                    }
                    actionItemsSection
                    if viewModel.isOCRSectionVisible {
                        reviewSection(
                            title: "OCR Text",
                            isLoading: viewModel.isOCRLoading,
                            content: viewModel.ocrText,
                            isFailed: viewModel.didOCRFail,
                            loadingPlaceholder: "Reading text…",
                            errorPlaceholder: "Couldn't read text from the photo",
                            emptyPlaceholder: "No text detected"
                        )
                    }
                    meetingSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .task {
                viewModel.analyze()
            }
            .alert(
                "Couldn't analyze the photo",
                isPresented: $viewModel.isSummarizeFailureAlertPresented,
                presenting: viewModel.summarizeFailure
            ) { _ in
                Button("Retry") {
                    viewModel.retrySummarize()
                }
                Button("Dismiss", role: .cancel) {}
            } message: { failure in
                Text(failure.alertText)
            }
            .sheet(isPresented: $isMeetingPickerPresented) {
                WBiOSMeetingPickerView(
                    meetings: viewModel.meetings,
                    selectedID: viewModel.selectedMeetingID
                ) { meeting in
                    viewModel.selectedMeetingID = meeting.id
                }
            }
            .navigationDestination(isPresented: $isShowingResult) {
                if let meeting = viewModel.selectedMeeting {
                    WBiOSSaveResultView(
                        image: viewModel.image,
                        title: viewModel.title,
                        summary: viewModel.summary,
                        ocrText: viewModel.ocrText,
                        actionItems: viewModel.actionItemTexts,
                        meeting: meeting,
                        onFinish: { dismiss() },
                        onSaved: onSaved
                    )
                }
            }
            .navigationTitle("Review & Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Leaving without saving — stop the LLM call and Vision recognition rather
                        // than letting them run on for a capture that's being discarded.
                        viewModel.cancelAnalysis()
                        dismiss()
                    }
                    .tint(Color.plainButtonText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isShowingResult = true
                    }
                    .tint(Color.plainButtonText)
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }

    /// Overlay button to discard the current photo and capture again — swaps the image in place.
    /// Confirms first when the user has action items of their own on screen, since a retake discards
    /// them; with nothing to lose it goes straight to the camera.
    private var retakeButton: some View {
        Button {
            if viewModel.shouldConfirmRetake {
                isRetakeConfirmationPresented = true
            } else {
                captureModel.start()
            }
        } label: {
            Label("Retake", systemImage: "camera")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentButtonText)
                .padding(.horizontal, .spacingMD)
                .padding(.vertical, .spacingSM)
                .background(Color.accentButtonBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: .radiusMD))
        }
        .buttonStyle(.plain)
        .imageCapture(captureModel) { image in
            viewModel.setImage(image)
        }
        .alert("Retake photo?", isPresented: $isRetakeConfirmationPresented) {
            Button("Retake", role: .destructive) {
                captureModel.start()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The action items you added yourself will be discarded.")
        }
        .padding(.spacingMD)
    }

    /// Retry for a failed generation run, shown under the sections it would refill. The pop-up
    /// carries the same action, but it's gone as soon as it's dismissed — this stays until the run
    /// is retried, so tapping Dismiss doesn't strand the user with a retake as the only way out.
    private var retrySummarizeButton: some View {
        Button {
            viewModel.retrySummarize()
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentButtonText)
                .padding(.horizontal, .spacingMD)
                .frame(height: .buttonHeightMD)
                .background(Color.accentButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: .radiusMD))
        }
        .buttonStyle(.plain)
    }

    /// A titled section of the review form, in one of four states, checked in this order:
    /// generating (`isLoading` → spinner beside the header + `loadingPlaceholder`), generated
    /// (`content`), failed (`isFailed` → `errorPlaceholder`), or succeeded with nothing to show
    /// (`emptyPlaceholder`).
    ///
    /// Failure and emptiness are deliberately separate inputs rather than both inferred from blank
    /// content: for OCR the two are genuinely different outcomes, and keying an error message off
    /// "content is empty" would make it a state the section could fall into by accident. Every
    /// placeholder renders in secondary style, to read as status rather than as content.
    private func reviewSection(
        title: String,
        isLoading: Bool = false,
        content: String? = nil,
        isFailed: Bool = false,
        loadingPlaceholder: String? = nil,
        errorPlaceholder: String? = nil,
        emptyPlaceholder: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacingSM) {
            HStack(spacing: .spacingSM) {
                sectionHeader(title)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if isLoading {
                placeholderText(loadingPlaceholder)
            } else if let content, !content.isEmpty {
                Text(content)
                    .font(.body)
            } else if isFailed {
                placeholderText(errorPlaceholder)
            } else {
                placeholderText(emptyPlaceholder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Secondary-styled status line under a section header. Renders nothing when the section didn't
    /// supply a placeholder for the state it's in.
    @ViewBuilder
    private func placeholderText(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    /// The tasks the LLM read off the whiteboard, one row each, closing with the "Add Action Item"
    /// row. Always shown — that trailing row is the entry point for adding one by hand, so it has to
    /// be reachable even when the whiteboard recorded no tasks and even while generation is still
    /// running.
    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: .spacingSM) {
            sectionHeader("Action Items")
            ForEach(viewModel.actionItems) { item in
                WBiOSActionItemRow(
                    id: item.id,
                    text: item.text,
                    openRow: $openActionItemRow,
                    onEdit: {
                        // Close the swipe, or the row stays open behind the prompt and after it goes.
                        openActionItemRow = nil
                        editingActionItemID = item.id
                        draftActionItem = item.text
                        isActionItemPromptPresented = true
                    },
                    onDelete: {
                        openActionItemRow = nil
                        withAnimation(.snappy) {
                            viewModel.deleteActionItem(id: item.id)
                        }
                    }
                )
            }
            // Styled as a filled accent button rather than another list row — as a plain row it read
            // as a fourth action item instead of a control. Follows Home's capture button, but at
            // `buttonHeightMD` since this is a secondary action on a crowded screen, not the primary
            // call to action. That's still the 44pt minimum tap target.
            Button {
                editingActionItemID = nil
                draftActionItem = ""
                isActionItemPromptPresented = true
            } label: {
                Label("Add Action Item", systemImage: "plus")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: .buttonHeightMD)
                    .background(Color.accentButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: .radiusMD))
            }
            .buttonStyle(.plain)
            .padding(.top, .spacingMD)
            .disabled(viewModel.isActionItemsLoading)
            // `.plain` doesn't dim its own content when disabled, so fade it explicitly — same
            // pattern as Home's capture button.
            .opacity(viewModel.isActionItemsLoading ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One prompt for both modes rather than two near-identical alerts, so the placeholder, the
        // blank-input gate, and the button behaviour can't drift apart. `editingActionItemID` is what
        // distinguishes them: nil appends, non-nil rewrites that row.
        .alert(
            editingActionItemID == nil ? "Add Action Item" : "Edit Action Item",
            isPresented: $isActionItemPromptPresented
        ) {
            TextField("Action item", text: $draftActionItem)
            Button("Cancel", role: .cancel) {
                editingActionItemID = nil
            }
            Button("OK") {
                if let editingActionItemID {
                    viewModel.updateActionItem(id: editingActionItemID, text: draftActionItem)
                } else {
                    viewModel.addActionItem(draftActionItem)
                }
                editingActionItemID = nil
            }
            .disabled(isDraftActionItemBlank)
        }
    }

    /// Header for a section of the review form. A step up in **both** size and weight from the body
    /// text beneath it: `.headline` is the same 17pt as `.body` and differs only in weight, which
    /// wasn't enough separation to read as a heading.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
    }

    /// Whether the typed action item is empty once trimmed — gates the prompt's OK button so a blank
    /// row can't be added or an existing one blanked.
    private var isDraftActionItemBlank: Bool {
        draftActionItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: .spacingSM) {
            sectionHeader("Meeting")
            if let meeting = viewModel.selectedMeeting {
                WBiOSMeetingRowView(meeting: meeting) {
                    isMeetingPickerPresented = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
