#if canImport(UIKit)
import Observation

/// A feature-owned observable source for a reactive Screen.
///
/// The feature should retain the state while it expects the screen to update.
/// The controller's internal state reader holds state weakly, but retained
/// client closures or item values may hold it strongly. If state is released
/// after the initial snapshot is applied, the controller keeps that snapshot
/// and receives no further state updates.
@MainActor
public protocol ScreenState: AnyObject, Observable {
    associatedtype Section: ScreenSectionModel

    /// The current ordered sections rendered by the screen.
    var sections: [Section] { get }
}
#endif
