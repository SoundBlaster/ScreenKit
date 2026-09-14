#if canImport(UIKit)
import UIKit

/// Creates a standard navigation controller containing one root screen.
@MainActor
public struct NavigationScreen<Root: ScreenRepresentable>: ScreenRepresentable {
    private let root: Root

    public init(_ root: Root) {
        self.root = root
    }

    public func makeViewController() -> UINavigationController {
        UINavigationController(rootViewController: root.makeViewController())
    }
}

extension ScreenRepresentable {
    public func navigation() -> NavigationScreen<Self> {
        NavigationScreen(self)
    }
}
#endif
