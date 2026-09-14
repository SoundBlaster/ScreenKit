#if canImport(UIKit)
import UIKit

/// One supplementary kind with separate dequeue and in-place update operations.
@MainActor
public struct ScreenSupplementaryRenderer<SectionID> {
    public let elementKind: String
    private let make: (UICollectionView, IndexPath) -> UICollectionReusableView
    private let configure: (UICollectionReusableView, SectionID) -> Void

    public init<Content: UICollectionReusableView>(
        elementKind: String,
        make: @escaping (UICollectionView, IndexPath) -> Content,
        update: @escaping (Content, SectionID) -> Void
    ) {
        self.elementKind = elementKind
        self.make = make
        configure = { view, sectionID in
            guard let content = view as? Content else {
                preconditionFailure("Supplementary view does not match its renderer")
            }
            update(content, sectionID)
        }
    }

    internal func view(in collection: UICollectionView, at indexPath: IndexPath, sectionID: SectionID) -> UICollectionReusableView {
        let view = make(collection, indexPath)
        configure(view, sectionID)
        return view
    }

    internal func update(_ view: UICollectionReusableView, sectionID: SectionID) {
        configure(view, sectionID)
    }
}
#endif
