import SwiftUI

/// Root bottom-tab navigation for the iOS app.
struct WBiOSRootTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                WBiOSHomeView()
            }
            Tab("Meetings", systemImage: "calendar") {
                WBiOSMeetingsView()
            }
            Tab("Search", systemImage: "magnifyingglass") {
                WBiOSSearchView()
            }
            Tab("Settings", systemImage: "gearshape") {
                WBiOSSettingsView()
            }
        }
        .tint(Color.plainButtonText)
    }
}

#Preview {
    WBiOSRootTabView()
}
