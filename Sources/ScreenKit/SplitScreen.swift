#if canImport(UIKit)
import UIKit

/// Composes primary and secondary screens using UIKit's two-column adaptation.
@MainActor
public struct SplitScreen<Primary: ScreenRepresentable, Secondary: ScreenRepresentable>: ScreenRepresentable {
    private let primary: Primary
    private let secondary: Secondary

    public init(primary: Primary, secondary: Secondary) {
        self.primary = primary
        self.secondary = secondary
    }

    public func makeViewController() -> UISplitViewController {
        let controller = UISplitViewController(style: .doubleColumn)
        controller.setViewController(primary.makeViewController(), for: .primary)
        controller.setViewController(secondary.makeViewController(), for: .secondary)
        return controller
    }
}
#endif
