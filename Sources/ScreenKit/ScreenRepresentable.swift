#if canImport(UIKit)
import UIKit

/// A screen description that creates its UIKit controller on demand.
@MainActor
public protocol ScreenRepresentable {
    associatedtype Controller: UIViewController

    func makeViewController() -> Controller
}

/// Adapts an existing controller factory for composition. Return a fresh controller
/// from the factory each time so separate container trees do not share children.
@MainActor
public struct ControllerScreen<Controller: UIViewController>: ScreenRepresentable {
    private let make: @MainActor () -> Controller

    public init(_ make: @escaping @MainActor () -> Controller) {
        self.make = make
    }

    public func makeViewController() -> Controller {
        make()
    }
}

/// Erases the concrete controller type where heterogeneous screens meet.
@MainActor
public struct AnyScreen: ScreenRepresentable {
    private let make: @MainActor () -> UIViewController

    public init<Content: ScreenRepresentable>(_ content: Content) {
        make = { content.makeViewController() }
    }

    public func makeViewController() -> UIViewController {
        make()
    }
}
#endif
