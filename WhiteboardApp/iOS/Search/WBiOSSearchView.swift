import SwiftUI

/// Search tab — placeholder for the initial version.
struct WBiOSSearchView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("Coming soon.")
            )
            .navigationTitle("Search")
        }
    }
}

#Preview {
    WBiOSSearchView()
}
