# ``ScreenKit``

Build UIKit screens as values and create a `UIViewController` only when a screen
enters a UIKit composition tree. ScreenKit owns the collection view, diffable
data source, and snapshot lifecycle; applications keep ownership of their models
and state.

The package targets iOS 18 and later. Its public surface is UIKit-first and does
not require a base view-controller subclass.

## Start with a screen

Use ``screen(_:renderer:)->Screen<Int,Item>`` for a single-section list. The macro forwards to
`Screen(items, renderer:)`; it does not create state or change the renderer
lifecycle.

```swift
import ScreenKit

struct Product: Identifiable, Sendable {
    let id: UUID
    let title: String
}

let products: [Product] = loadProducts()
let screen = #screen(products) { product in
    ScreenCellRenderer { collection, indexPath, item in
        let cell = collection.dequeueReusableCell(
            withReuseIdentifier: "Product",
            for: indexPath
        )
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        cell.contentConfiguration = content
        return cell
    }
}
    .title { "Products" }

let controller = screen.makeViewController()
```

Register the cell identifier with the collection view before it is requested, or
return a cell from a `UICollectionView.CellRegistration`-based renderer. For
multiple sections, construct ``Screen`` with ``ScreenSection`` values.

## Update content

A screen controller exposes explicit update methods for stateless screens. Item
identifiers must be unique across the whole screen, and section identifiers must
be unique.

```swift
controller.setItems(updatedProducts)
controller.refreshContent()
```

Use `setSections(_:animated:completion:)` for multiple sections. On a screen
created from `ScreenState`, calls to `setItems` or `setSections` are ignored and
logged; their completion closures are not called. Mutate the feature-owned state
instead. ScreenKit tracks observable reads made by reactive screens, including
custom layout and supplementary renderers, on iOS 18 and later.
``ScreenViewController/invalidateLayout()`` remains available when layout inputs
are not observable; iOS 27 can additionally provide native layout observation.

## Make state changes reactive

Feature-owned `@Observable` models can conform to ``ScreenState``. The
`#screen(state)` entry point tracks the state values read by the screen and
schedules animated snapshot updates on the main actor. Mutations observed before
a scheduled update may be applied together; this is not a transaction boundary.
`itemIDs` and `sectionIDs` report the currently applied snapshot and may briefly
lag behind the state. ScreenKit uses `Observation.withObservationTracking`, so
no observation-specific Info.plist key is required.

The feature should retain the state while it expects the screen to update. The
controller's internal state reader holds it weakly, but retained renderers,
title, layout, or supplementary closures and item values can capture it
strongly. If none of those retained values keeps state alive, releasing it
before the first read makes the screen start empty; releasing it after a
snapshot is applied leaves the controller showing that snapshot with no further
state updates.

```swift
import Observation

@MainActor
@Observable
final class ProductsState: ScreenState {
    var sections: [ProductsSection] = []
}

let state = ProductsState()
let screen = #screen(state) { product in
    productRenderer
}
let controller = screen.makeViewController()

state.sections.append(newSection)
```

Use ``StableIdentifiable`` for items and ``ScreenSectionModel`` for typed
sections. IDs must remain stable for the lifetime of an entity. Section IDs
must be unique among sections; item IDs must be unique across the whole screen.
These are separate identity namespaces, so a section ID and item ID may have
the same value and Swift type.
``ScreenViewController/setItems(_:animated:completion:)`` and
``ScreenViewController/setSections(_:animated:completion:)`` remain available
for stateless screens. New conforming models may need an explicit
`typealias ID = UUID` (or another `Hashable & Sendable` ID type). Reactive
screens use `stableID` for their diffable-data-source identity, even when a
legacy model's `id` has a different value of the same type.

``StableIdentifiable`` refines `Identifiable`; both properties therefore share
one associated `ID` type. This new model can supply only `stableID`:

```swift
struct SearchResult: StableIdentifiable, Sendable {
    typealias ID = UUID
    let stableID: ID
    let title: String
}
```

An existing `Identifiable` model can add ``StableIdentifiable`` in an
integration module when its existing `ID` type matches the type returned by
`stableID`. If those types differ, use an adapter model or change the model's
`Identifiable.ID` contract; an extension cannot declare a second associated
`ID` type for the same conformance.

## Compose screens

Every ``ScreenRepresentable`` creates its controller on demand. Use
``ControllerScreen`` to adapt a legacy controller factory and ``AnyScreen``
when a collection needs to hold different screen types.

- Navigation: ``NavigationScreen`` and `navigation()`
- Tabs: ``TabsScreen`` and ``ScreenTab``
- Pages: ``PagesScreen``
- Split view: ``SplitScreen``

## Topics

### Define and render screens

- ``Screen``
- ``ScreenState``
- ``StableIdentifiable``
- ``ScreenSectionModel``
- ``screen(_:renderer:)->Screen<Int,Item>``
- ``ScreenSection``
- ``ScreenCellRenderer``
- ``ScreenSupplementaryRenderer``
- ``ScreenViewController``

### Adapt and compose screens

- ``ScreenRepresentable``
- ``ControllerScreen``
- ``AnyScreen``
- ``NavigationScreen``
- ``ScreenTab``
- ``TabsScreen``
- ``PagesScreen``
- ``SplitScreen``

## Migration tutorial

- <doc:UIKitCollectionMigration>

## See Also

- [Continue by mixing legacy UIKit and SwiftUI content with Patchwork](https://soundblaster.github.io/Patchwork/tutorials/patchwork/uikitmigrationwithpatchwork/)
