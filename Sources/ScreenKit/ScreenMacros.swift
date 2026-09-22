#if canImport(UIKit)
/// Creates a single-section `Screen` while retaining the concise `#screen` entry point.
///
/// The macro forwards its arguments to `Screen.init(_:renderer:)`. It does not create
/// state, evaluate content early, or alter the renderer lifecycle.
@freestanding(expression)
public macro screen<Item: Identifiable where Item.ID: Sendable>(
    _ items: [Item],
    renderer: (Item) -> ScreenCellRenderer<Item>
) -> Screen<Int, Item> = #externalMacro(module: "ScreenKitMacros", type: "ScreenMacro")

/// Creates a reactive screen backed by a feature-owned observable state.
@freestanding(expression)
public macro screen<State: ScreenState>(
    _ state: State,
    renderer: (State.Section.Item) -> ScreenCellRenderer<State.Section.Item>
) -> Screen<State.Section.ID, State.Section.Item> = #externalMacro(module: "ScreenKitMacros", type: "ScreenMacro")
#endif
