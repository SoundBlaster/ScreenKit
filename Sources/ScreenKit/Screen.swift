#if canImport(UIKit)
import UIKit

/// A UIKit screen description. Client code does not subclass UIViewController.
@MainActor
public struct Screen<SectionID: Hashable & Sendable, Item: Identifiable>: ScreenRepresentable where Item.ID: Sendable {
    internal let sections: [ScreenSection<SectionID, Item>]
    internal let renderer: (Item) -> ScreenCellRenderer<Item>
    internal var titleProvider: () -> String = { "" }
    internal var sectionProvider: ((SectionID, NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection)?
    internal var supplementaryRenderers: [ScreenSupplementaryRenderer<SectionID>] = []

    public init(_ sections: [ScreenSection<SectionID, Item>], renderer: @escaping (Item) -> ScreenCellRenderer<Item>) {
        self.sections = sections
        self.renderer = renderer
    }

    public func title(_ value: @escaping () -> String) -> Self {
        var copy = self
        copy.titleProvider = value
        return copy
    }

    /// Section IDs remain stable across reordering. Observable reads are tracked on iOS 27.
    /// Earlier systems require invalidateLayout() after a layout model changes.
    public func layout(_ provider: @escaping (SectionID, NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection) -> Self {
        var copy = self
        copy.sectionProvider = provider
        return copy
    }

    /// Registers managed supplementary kinds with separate creation and update phases.
    public func supplementary(_ renderers: [ScreenSupplementaryRenderer<SectionID>]) -> Self {
        precondition(Set(renderers.map(\.elementKind)).count == renderers.count, "Supplementary kinds must be unique")
        var copy = self
        copy.supplementaryRenderers = renderers
        return copy
    }

    public func makeViewController() -> ScreenViewController<SectionID, Item> {
        ScreenViewController(screen: self)
    }
}

extension Screen where SectionID == Int {
    public init(_ items: [Item], renderer: @escaping (Item) -> ScreenCellRenderer<Item>) {
        self.init([ScreenSection(id: 0, items: items)], renderer: renderer)
    }

    public func layout(_ provider: @escaping (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection) -> Self {
        layout { _, environment in provider(environment) }
    }
}
#endif
