import SwiftUI

/// The add / edit / delete action-item prompt, shown as a sheet rather than an alert because it
/// has to **stay open while the change is being stored**: an alert dismisses itself the moment a
/// button is tapped, which would show the list as changed before the engine had it.
///
/// While saving, the field and buttons lock and the sheet reports what it is doing; it closes only
/// once the engine confirms the new version, and stays open with the reason if that doesn't happen.
struct WBMacOSActionItemPromptView: View {
    let prompt: WBMacOSActionItemsSectionViewModel.Prompt
    @Binding var text: String
    let isSaving: Bool
    let isTextBlank: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSubmit: () -> Void

    private static let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXL) {
            Text(prompt.title)
                .font(.headline)

            if case .delete(let item) = prompt {
                Text("\"\(item.text)\" will be removed from this whiteboard. This can't be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Action item", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isSaving)
                    .onSubmit(onSubmit)
            }

            status

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                confirmButton
            }
        }
        .padding(.spacing3XL)
        .frame(width: WBMacOSActionItemPromptView.width)
        // Stops a stray Escape or click-through from dismissing mid-write and leaving the user
        // unsure whether the change was saved.
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var status: some View {
        if isSaving {
            HStack(spacing: .spacingSM) {
                ProgressView()
                    .controlSize(.small)
                Text(prompt.isDelete ? "Deleting…" : "Saving…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage {
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmButton: some View {
        Button(prompt.isDelete ? "Delete" : "OK", role: prompt.isDelete ? .destructive : nil) {
            onSubmit()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(isSaving || (!prompt.isDelete && isTextBlank))
    }
}
