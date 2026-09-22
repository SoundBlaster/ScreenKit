#if canImport(UIKit)
/// An identifiable value whose identity remains stable while its content changes.
/// New conforming types should declare their ID type explicitly when Swift cannot
/// infer it from the stored `stableID` property, for example `typealias ID = UUID`.
public protocol StableIdentifiable: Identifiable where ID: Hashable & Sendable {
    /// The identity used by ScreenKit's diffable data source.
    var stableID: ID { get }
}

public extension StableIdentifiable {
    var id: ID { stableID }
}
#endif
