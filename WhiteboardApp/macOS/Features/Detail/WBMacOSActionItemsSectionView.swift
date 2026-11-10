import SwiftUI

/// The detail inspector's action items section: the shown whiteboard's own tasks, each
/// checkable and editable, closing with the "Add Action Item" button.
///
/// Always shown — that button is the entry point for adding an item by hand, so it stays
/// reachable even when the whiteboard recorded no tasks.
struct WBMacOSActionItemsSectionView: View {
    let whiteboard: WBMacOSWhiteboard?

    @State private var viewModel: WBMacOSActionItemsSectionViewModel

    /// The row the pointer is over — its Edit and Delete buttons are the only ones shown, so
    /// the list stays quiet until the user goes looking for them.
    @State private var hoveredItemID: String?

    init(
        whiteboard: WBMacOSWhiteboard?,
        actionItemsProvider: WBMacOSActionItemsProviding,
        onItemsChanged: @escaping ([WBMacOSActionItem]) -> Void
    ) {
        self.whiteboard = whiteboard
        _viewModel = State(
            initialValue: WBMacOSActionItemsSectionViewModel(
                actionItemsProvider: actionItemsProvider,
                onItemsChanged: onItemsChanged
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMD) {
            Text("Action Items")
                .font(.headline)
            ForEach($viewModel.items) { $item in
                row(for: $item)
            }
            // No error line here: every change is made from the prompt, which stays open and
            // reports its own failure — a copy behind the sheet would only ever be hidden.
            addButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: whiteboard, initial: true) {
            viewModel.show(whiteboard)
        }
        .sheet(item: $viewModel.prompt) { prompt in
            WBMacOSActionItemPromptView(
                prompt: prompt,
                text: $viewModel.draftText,
                isSaving: viewModel.isSaving,
                isTextBlank: viewModel.isDraftBlank,
                errorMessage: viewModel.saveErrorMessage,
                onCancel: { viewModel.cancelPrompt() },
                onSubmit: {
                    Task {
                        await viewModel.submitPrompt()
                    }
                }
            )
        }
    }

    /// One item: the checkable row, with Edit and Delete revealed on hover. Both are also on
    /// the row's context menu, which is what makes them reachable by keyboard and Control-click
    /// rather than only by pointing at the row.
    private func row(for item: Binding<WBMacOSActionItem>) -> some View {
        let id = item.wrappedValue.id
        return HStack(alignment: .firstTextBaseline, spacing: .spacingSM) {
            Toggle(isOn: item.isDone) {
                Text(item.wrappedValue.text)
                    .font(.body)
                    .strikethrough(item.wrappedValue.isDone)
                    .foregroundStyle(item.wrappedValue.isDone ? .secondary : .primary)
            }
            .toggleStyle(WBMacOSActionItemToggleStyle())
            rowActions(for: item.wrappedValue)
                .opacity(hoveredItemID == id ? 1 : 0)
        }
        .onHover { isHovering in
            hoveredItemID = isHovering ? id : (hoveredItemID == id ? nil : hoveredItemID)
        }
        .contextMenu {
            Button("Edit") {
                viewModel.beginEdit(item.wrappedValue)
            }
            .disabled(viewModel.isSaving)
            Button("Delete", role: .destructive) {
                viewModel.beginDelete(item.wrappedValue)
            }
            .disabled(viewModel.isSaving)
        }
    }

    private func rowActions(for item: WBMacOSActionItem) -> some View {
        HStack(spacing: .spacingSM) {
            Button {
                viewModel.beginEdit(item)
            } label: {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("Edit")
            Button {
                viewModel.beginDelete(item)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .hoverOpacity()
        .disabled(viewModel.isSaving)
    }

    /// Disabled while a save is in flight, so two writes can't race the same record — the
    /// item is only in the list once the engine has it.
    private var addButton: some View {
        Button {
            viewModel.beginAdd()
        } label: {
            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Add Action Item", systemImage: "plus")
            }
        }
        .buttonStyle(.borderedProminent)
        .hoverOpacity()
        .disabled(viewModel.isSaving || whiteboard == nil)
        .padding(.top, .spacingSM)
    }
}

/// Checkmark-glyph toggle: an empty circle that fills with a checkmark once the item is
/// done — matching how iOS marks action items — rather than the stock square checkbox.
/// Stays a `Toggle` so it keeps the checkbox's keyboard and VoiceOver behavior; the whole
/// row is the hit target, and the glyph is baseline-aligned so it sits on the text's first
/// line rather than floating when the item wraps.
private struct WBMacOSActionItemToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: .spacingSM) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                configuration.label
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverOpacity()
    }
}
