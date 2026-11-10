import Observation

/// View model for the sidebar: drives the selected destination through the shared selection
/// manager and hands the view its items per section.
@Observable
final class WBMacOSSidebarViewModel {

    private let manager: WBMacOSSelectionManager

    init(manager: WBMacOSSelectionManager) {
        self.manager = manager
    }

    /// Bindable selection for `List`, which needs an `Optional` and writes `nil` when empty
    /// sidebar space is clicked. Home is never "nothing selected", so `nil` writes are
    /// swallowed.
    var listSelection: WBMacOSSidebarItem? {
        get {
            manager.sidebarItem
        }
        set {
            guard let newValue else {
                return
            }
            manager.sidebarItem = newValue
        }
    }

    func items(in section: WBMacOSSidebarItem.Section) -> [WBMacOSSidebarItem] {
        WBMacOSSidebarItem.items(in: section)
    }
}
