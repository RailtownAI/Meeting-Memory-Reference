import SwiftUI

/// A single attendee: a circular portrait next to the attendee's name. The portrait
/// resolves from the user's Contacts (by email, then name); attendees who don't match, or
/// while the lookup is in flight, keep the placeholder.
struct WBiOSAttendeeView: View {
    let attendee: WBiOSAttendee

    @State private var viewModel = WBiOSAttendeeViewModel()

    var body: some View {
        HStack(spacing: .spacingSM) {
            portrait
            Text(attendee.name)
                .font(.subheadline)
                .lineLimit(1)
        }
        .task(id: attendee.id) {
            await viewModel.loadPortrait(for: attendee)
        }
    }

    private var portrait: some View {
        Group {
            if let contactPortrait = viewModel.portrait {
                Image(uiImage: contactPortrait)
                    .resizable()
                    .scaledToFill()
            } else if let image = attendee.portrait {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

/// Display model for an attendee shown in `WBiOSAttendeeView`.
struct WBiOSAttendee: Identifiable {
    let id: String
    let name: String
    /// Email, when known — used later to resolve a portrait from Contacts.
    let email: String?
    /// Portrait image; `nil` shows a placeholder.
    var portrait: Image?

    init(id: String, name: String, email: String? = nil, portrait: Image? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.portrait = portrait
    }
}

#Preview {
    WBiOSAttendeeView(attendee: WBiOSAttendee(id: "1", name: "Jane Doe"))
        .padding()
}
