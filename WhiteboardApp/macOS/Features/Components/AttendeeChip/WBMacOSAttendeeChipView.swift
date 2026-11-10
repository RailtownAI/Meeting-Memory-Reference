import SwiftUI

/// One attendee chip: the avatar and the display name. Shows the contact photo when the
/// attendee resolves in the user's Contacts, and an initials circle otherwise (also while
/// the lookup is in flight — avatars fade in, initials never flash into photos and back).
struct WBMacOSAttendeeChipView: View {
    let attendee: WBMacOSAttendee

    @State private var viewModel: WBMacOSAttendeeChipViewModel

    init(attendee: WBMacOSAttendee, imageProvider: WBMacOSAttendeeImageProviding) {
        self.attendee = attendee
        _viewModel = State(
            initialValue: WBMacOSAttendeeChipViewModel(imageProvider: imageProvider)
        )
    }

    private static let avatarSize: CGFloat = 24

    var body: some View {
        HStack(spacing: .spacingSM) {
            avatar
            Text(attendee.displayName)
                .font(.subheadline)
        }
        .task(id: attendee.id) {
            await viewModel.loadAvatar(for: attendee)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = viewModel.avatar {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: WBMacOSAttendeeChipView.avatarSize,
                    height: WBMacOSAttendeeChipView.avatarSize
                )
                .clipShape(Circle())
        } else {
            Text(initials)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(
                    width: WBMacOSAttendeeChipView.avatarSize,
                    height: WBMacOSAttendeeChipView.avatarSize
                )
                .background(.quinary, in: Circle())
        }
    }

    private var initials: String {
        let words = attendee.displayName.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined()
    }
}
