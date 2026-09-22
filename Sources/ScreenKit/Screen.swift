#if canImport(UIKit)
import UIKit

/// A UIKit screen description. Client code does not subclass UIViewController.
@MainActor
public struct Screen<SectionID: Hashable & Sendable, Item: Identifiable>: ScreenRepresentable where Item.ID: Sendable {
    internal let sections: [ScreenSection<SectionID, Item>]
    internal let renderer: (Item) -> ScreenCellRenderer<Item>
    internal var itemIDProvider: ((Item) -> Item.ID)? = nil
    internal var stateReader: (@MainActor () -> [ScreenSection<SectionID, Item>])?
    internal var titleProvider: () -> String = { "" }
    internal var sectionProvider: ((SectionID, NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection)?
    internal var supplementaryRenderers: [ScreenSupplementaryRenderer<SectionID>] = []

    public init(_ sections: [ScreenSection<SectionID, Item>], renderer: @escaping (Item) -> ScreenCellRenderer<Item>) {
        self.sections = sections
        self.renderer = renderer
    }

    /// Creates a reactive screen from a feature-owned observable state.
    public init<State: ScreenState>(
        _ state: State,
        renderer: @escaping (State.Section.Item) -> ScreenCellRenderer<State.Section.Item>
    ) where SectionID == State.Section.ID, Item == State.Section.Item {
        self.init([], renderer: renderer)
        itemIDProvider = { $0.stableID }
        stateReader = { [weak state] in
            guard let state else { return [] }
            return state.sections.map { section in
                ScreenSection(id: section.stableID, items: section.items)
            }
        }
    }

    public func title(_ value: @escaping () -> String) -> Self {
        var copy = self
        copy.titleProvider = value
        return copy
    }

    /// Section IDs remain stable across reordering. Reactive screens track
    /// observable layout reads on iOS 18 and later.
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
