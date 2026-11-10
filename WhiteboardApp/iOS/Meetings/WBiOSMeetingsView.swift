import SwiftUI

/// Meetings tab — placeholder for the initial version.
struct WBiOSMeetingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Meetings",
                systemImage: "calendar",
                description: Text("Coming soon.")
            )
            .navigationTitle("Meetings")
        }
    }
}

#Preview {
    WBiOSMeetingsView()
}
