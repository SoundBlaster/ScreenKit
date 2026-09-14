#if canImport(UIKit)
/// Stable section identity and ordered items. Item IDs are unique across the screen.
public struct ScreenSection<ID: Hashable & Sendable, Item>: Identifiable {
    public let id: ID
    public var items: [Item]

    public init(id: ID, items: [Item]) {
        self.id = id
        self.items = items
    }
}
#endif
