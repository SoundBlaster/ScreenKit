# ScreenKit

[![DocC](https://github.com/SoundBlaster/ScreenKit/actions/workflows/documentation.yml/badge.svg?branch=main)](https://github.com/SoundBlaster/ScreenKit/actions/workflows/documentation.yml)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://soundblaster.github.io/ScreenKit/)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-lightgrey?logo=apple)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

ScreenKit builds UIKit screens as values. A screen describes its content and
creates a fresh `UIViewController` only at the composition boundary; application
code does not need to subclass `UIViewController`.

The package targets iOS 18 and later. It owns one collection view, one diffable
data source, and the complete snapshot/update lifecycle for each `Screen`.
Sections and items have stable typed identity, and renderers can be retained
across updates.

```swift
import ScreenKit

let screen = #screen(items) { item in
    // Return a ScreenCellRenderer supplied by ScreenKit or an adapter package.
}
    .title { "Products" }

let controller = screen.makeViewController()
```

`#screen(items, renderer:)` is a stateless convenience for the single-section
initializer. Use `Screen([ScreenSection(...)], renderer:)` when section identities
or multiple sections are needed. The macro does not own screen state; application
features continue to own their models and updates. To write the single-section
initializer explicitly, use `Screen(items, renderer: renderer)`.

For automatic updates, make a feature-owned model conform to `ScreenState` and
use `#screen(state)`. ScreenKit tracks the state values read while describing
the screen and schedules animated snapshot updates on the main actor. Several
mutations observed before a scheduled update may be applied together; this is
not a transaction boundary. ID accessors report the applied snapshot and may
briefly lag behind state. Item and section models must provide stable IDs through
`StableIdentifiable`.

The feature should retain state while it expects the screen to update. The
controller's internal state reader holds state weakly, but retained renderers,
title, layout, or supplementary closures and item values can capture it strongly.
When none of those retained values keeps state alive, releasing it before the
first read makes the screen start empty; releasing it after a snapshot is
applied leaves the controller showing that last snapshot with no further state
updates.

`setSections` and `setItems` update stateless screens. Calls on state-backed
screens are ignored and logged, and their completion closures are not called;
change `state.sections` instead. `refreshContent`,
`refreshSupplementaryContent`, and `invalidateLayout` remain available when an
input is not observable.

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

state.sections.append(newSection) // the screen updates automatically
```

Existing models can adopt the identity contract in an integration module:

```swift
extension LegacyProduct: StableIdentifiable {
    var stableID: UUID { legacyID }
}
```

`StableIdentifiable` refines `Identifiable`, so `id` and `stableID` have the
same associated `ID` type (`Hashable & Sendable`). A new model can implement
only `stableID`; declare `typealias ID` when Swift cannot infer the associated
type:

```swift
struct SearchResult: StableIdentifiable, Sendable {
    typealias ID = UUID
    let stableID: ID
    let title: String
}
```

If a legacy model already conforms to `Identifiable`, its existing `ID` type
must also be the type returned by `stableID`. A computed `stableID` is a
convenient adapter when the legacy `id` uses the right type. If it uses a
different type, add an adapter model or change the model's `Identifiable.ID`
contract; an extension cannot give one conformance two different `ID` types.
Reactive screens use `stableID` for item and section identities, even when a
legacy model's `id` has a different value of the same type.

Section and item identities occupy separate namespaces: section IDs must be
unique among sections, while item IDs must be unique across all sections. A
section ID and an item ID may have equal values, even when they use the same
Swift type.

`ControllerScreen` adapts an existing controller factory during incremental
migration. `NavigationScreen`, `TabsScreen`, `PagesScreen`, and `SplitScreen`
compose screens without introducing a base controller type.

ScreenKit deliberately does not define product models, business actions, or a
state manager. It fits below page and flow modules in an FSD-style architecture.

## Documentation

Browse the [ScreenKit API documentation](https://soundblaster.github.io/ScreenKit/).
The implementation roadmap for state, identity, and observation is documented
in [`ROADMAP.md`](ROADMAP.md).

## Development

UIKit tests run from an iOS simulator. The app-level ScreenKitLab integration
tests live in the Puzzle workspace while the package is being extracted from the
prototype.

## License

MIT. See [LICENSE](LICENSE).
