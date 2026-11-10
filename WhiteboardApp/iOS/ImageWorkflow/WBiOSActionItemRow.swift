import SwiftUI

/// One row of the review screen's Action Items list, with Edit and Delete revealed by a leftward
/// swipe.
///
/// The review screen is a `ScrollView`, not a `List`, so `.swipeActions` isn't available and the
/// gesture is built by hand. The trick that keeps it simple: `.offset` is a purely visual transform,
/// so the row's layout frame never moves while its content slides. The revealed buttons live in an
/// overlay pinned to that unmoved trailing edge, parked just outside it when closed.
///
/// `openRow` is shared across every row, so opening one closes whichever was open before.
struct WBiOSActionItemRow: View {
    /// The item's stable id — what `openRow` names, so a deletion elsewhere in the list can't make
    /// some other row read as the open one.
    let id: UUID
    let text: String
    @Binding var openRow: UUID?
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Edge length of one action square. The pair together is how far the content slides.
    private static let actionWidth: CGFloat = 64
    private static let revealWidth = actionWidth * 2

    /// How far the content is currently slid, from 0 (closed) to `-revealWidth` (fully open).
    @State private var offset: CGFloat = 0

    var body: some View {
        content
            .offset(x: offset)
            // Applied *after* `.offset` so the layout box — and the overlay hung off it — stay put
            // while the content slides out from underneath.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Declared before the buttons so it sits *under* them: it covers the whole row for
            // swiping, while taps on a revealed Edit/Delete reach the buttons on top.
            .overlay {
                WBiOSHorizontalPanCatcher(onChanged: dragChanged, onEnded: dragEnded)
            }
            .overlay(alignment: .trailing) {
                actionButtons
                    // Parked one full reveal-width past the trailing edge at rest, sliding flush as
                    // `offset` goes negative.
                    .offset(x: Self.revealWidth + offset)
            }
            .clipShape(RoundedRectangle(cornerRadius: .radiusSM))
            .onChange(of: openRow) { _, newValue in
                guard newValue != id, offset != 0 else {
                    return
                }
                withAnimation(.snappy) {
                    offset = 0
                }
            }
            // The swipe is invisible to VoiceOver, so both actions get an explicit rotor entry.
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Edit", onEdit)
            .accessibilityAction(named: "Delete", onDelete)
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: .spacingSM) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.plainButtonText)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: "pencil",
                tint: Color.accentButtonText,
                background: Color.accentButtonBackground,
                label: "Edit",
                action: onEdit
            )
            actionButton(
                icon: "trash",
                tint: .white,
                background: .red,
                label: "Delete",
                action: onDelete
            )
        }
    }

    /// One square action. `maxHeight: .infinity` resolves against the row's own height, since the
    /// overlay is proposed the size of the view it decorates — so the squares always match the row,
    /// however many lines the item wraps to.
    private func actionButton(
        icon: String,
        tint: Color,
        background: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: Self.actionWidth)
                .frame(maxHeight: .infinity)
                .background(background)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Tracks the finger. No axis check needed — the catcher only reports horizontal drags.
    private func dragChanged(_ translation: CGFloat) {
        offset = clampedOffset(for: translation)
    }

    /// Snaps open or shut depending on which side of halfway the finger left off.
    private func dragEnded(_ translation: CGFloat) {
        let shouldOpen = clampedOffset(for: translation) < -Self.revealWidth / 2
        withAnimation(.snappy) {
            offset = shouldOpen ? -Self.revealWidth : 0
        }
        openRow = shouldOpen ? id : nil
    }

    /// Where the row sits for a given drag, measured from wherever it started and bounded by the
    /// buttons' width. Derived from the translation rather than read back off `offset`, so the
    /// end-of-drag decision can't act on a stale render.
    private func clampedOffset(for translation: CGFloat) -> CGFloat {
        let base: CGFloat = openRow == id ? -Self.revealWidth : 0
        return min(0, max(-Self.revealWidth, base + translation))
    }
}
