#if canImport(UIKit)
import UIKit

/// A reusable cell registration. Retain renderers across screen updates.
/// ScreenKit owns the data source; the renderer only dequeues/configures its cell.
@MainActor
public struct ScreenCellRenderer<Item> {
    internal let identity = UUID()
    private let provider: (UICollectionView, IndexPath, Item) -> UICollectionViewCell

    public init(
        provider: @escaping (UICollectionView, IndexPath, Item) -> UICollectionViewCell
    ) {
        self.provider = provider
    }

    public func cell(in collection: UICollectionView, at indexPath: IndexPath, item: Item) -> UICollectionViewCell {
        provider(collection, indexPath, item)
    }
}
#endif
