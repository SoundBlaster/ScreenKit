import UIKit

struct Product: Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let detail: String
}

@MainActor
final class ProductsViewController: UIViewController {
    private let products: [Product]
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Product>!

    private lazy var registration = UICollectionView.CellRegistration<UICollectionViewListCell, Product> { cell, _, product in
        var content = UIListContentConfiguration.subtitleCell()
        content.text = product.name
        content.secondaryText = product.detail
        cell.contentConfiguration = content
    }

    init(products: [Product]) {
        self.products = products
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(products:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Products"

        let layout = UICollectionViewCompositionalLayout.list(
            using: UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        )
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        dataSource = UICollectionViewDiffableDataSource<Int, Product>(collectionView: collectionView) { [weak self] collection, indexPath, product in
            guard let self else { return nil }
            return collection.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: product
            )
        }
        apply(products)
    }

    private func apply(_ products: [Product]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Product>()
        snapshot.appendSections([0])
        snapshot.appendItems(products, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}
