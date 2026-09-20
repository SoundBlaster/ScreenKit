# ``ScreenKit``

Build UIKit screens as values and create a `UIViewController` only when a screen
enters a UIKit composition tree. ScreenKit owns the collection view, diffable
data source, and snapshot lifecycle; applications keep ownership of their models
and state.

The package targets iOS 18 and later. Its public surface is UIKit-first and does
not require a base view-controller subclass.

## Start with a screen

Use ``screen(_:renderer:)`` for a single-section list. The macro forwards to
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

A screen controller exposes explicit update methods. Item identifiers must be
unique across the whole screen, and section identifiers must be unique.

```swift
controller.setItems(updatedProducts)
controller.refreshContent()
```

Use `setSections(_:animated:completion:)` for multiple sections. If the model
behind a custom layout changes on iOS 18–26, call ``ScreenViewController/invalidateLayout()``;
iOS 27 can track observable reads made by the layout provider.

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
- ``screen(_:renderer:)``
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
