#if canImport(UIKit)
/// A section model with stable identity and an ordered collection of items.
public protocol ScreenSectionModel: StableIdentifiable {
    associatedtype Item: StableIdentifiable

    var items: [Item] { get }
}
#endif
