#if canImport(UIKit)
import Observation

/// A feature-owned observable source for a reactive Screen.
@MainActor
public protocol ScreenState: AnyObject, Observable {
    associatedtype Section: ScreenSectionModel

    /// The current ordered sections rendered by the screen.
    var sections: [Section] { get }
}
#endif
