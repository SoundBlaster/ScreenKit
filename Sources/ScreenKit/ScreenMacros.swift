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
///
/// The feature should retain `state` while it expects the screen to update.
/// The internal state reader holds it weakly, though retained client closures
/// and item values may hold it strongly. Mutate the state's sections to change
/// screen structure; controller `setSections` and `setItems` calls are ignored
/// for state-backed screens.
@freestanding(expression)
public macro screen<State: ScreenState>(
    _ state: State,
    renderer: (State.Section.Item) -> ScreenCellRenderer<State.Section.Item>
) -> Screen<State.Section.ID, State.Section.Item> = #externalMacro(module: "ScreenKitMacros", type: "ScreenMacro")
#endif
