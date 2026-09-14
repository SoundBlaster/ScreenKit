#if canImport(UIKit)
import UIKit

/// Tab identity and presentation metadata are independent of the child title.
@MainActor
public struct ScreenTab {
    public let id: String
    public let title: String
    public let image: UIImage?
    public let content: AnyScreen

    public init(id: String, title: String, image: UIImage? = nil, content: AnyScreen) {
        self.id = id
        self.title = title
        self.image = image
        self.content = content
    }
}

/// Creates native iOS 18 tabs with stable identifiers and explicit labels.
@MainActor
public struct TabsScreen: ScreenRepresentable {
    private let tabs: [ScreenTab]
    private let selectedID: String?

    public init(_ tabs: [ScreenTab], selectedID: String? = nil) {
        precondition(Set(tabs.map(\.id)).count == tabs.count, "Tab IDs must be unique")
        precondition(selectedID == nil || tabs.contains { $0.id == selectedID }, "Selected tab ID must exist")
        self.tabs = tabs
        self.selectedID = selectedID
    }

    public func makeViewController() -> UITabBarController {
        let controller = UITabBarController()
        let nativeTabs = tabs.map { tab in
            UITab(title: tab.title, image: tab.image, identifier: tab.id) { _ in
                tab.content.makeViewController()
            }
        }
        controller.tabs = nativeTabs
        controller.selectedTab = nativeTabs.first { $0.identifier == selectedID } ?? nativeTabs.first
        return controller
    }
}
#endif
