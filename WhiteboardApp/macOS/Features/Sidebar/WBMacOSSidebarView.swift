import SwiftUI

/// Column 1: the "Meeting Memory" sidebar. Builds and owns its view model from the injected
/// dependencies.
struct WBMacOSSidebarView: View {

    @State private var viewModel: WBMacOSSidebarViewModel

    init(manager: WBMacOSSelectionManager) {
        _viewModel = State(initialValue: WBMacOSSidebarViewModel(manager: manager))
    }

    var body: some View {
        List(selection: $viewModel.listSelection) {
            Section {
                rows(for: .primary)
            }
            Section("Browse") {
                rows(for: .browse)
            }
            Section("Smart Lists") {
                rows(for: .smartLists)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Meeting Memory")
    }

    private func rows(for section: WBMacOSSidebarItem.Section) -> some View {
        ForEach(viewModel.items(in: section)) { item in
            Label(item.title, systemImage: item.systemImage)
                .tag(item)
        }
    }
}

#Preview {
    NavigationSplitView {
        WBMacOSSidebarView(manager: WBMacOSSelectionManager())
    } detail: {
        Text("Detail")
    }
}
