# ScreenKit

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

`ControllerScreen` adapts an existing controller factory during incremental
migration. `NavigationScreen`, `TabsScreen`, `PagesScreen`, and `SplitScreen`
compose screens without introducing a base controller type.

ScreenKit deliberately does not define product models, business actions, or a
state manager. It fits below page and flow modules in an FSD-style architecture.

## Documentation

Browse the [ScreenKit API documentation](https://soundblaster.github.io/ScreenKit/).

## Development

UIKit tests run from an iOS simulator. The app-level ScreenKitLab integration
tests live in the Puzzle workspace while the package is being extracted from the
prototype.

## License

MIT. See [LICENSE](LICENSE).
