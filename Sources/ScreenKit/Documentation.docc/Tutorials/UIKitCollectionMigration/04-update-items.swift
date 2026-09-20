import ScreenKit
import UIKit

struct Product: Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let detail: String
}

@MainActor
func productsScreen(_ products: [Product]) -> Screen<Int, Product> {
    let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Product> { cell, _, product in
        var content = UIListContentConfiguration.subtitleCell()
        content.text = product.name
        content.secondaryText = product.detail
        cell.contentConfiguration = content
    }
    let renderer = ScreenCellRenderer<Product> { collection, indexPath, product in
        collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: product)
    }
    return #screen(products) { _ in renderer }
        .title { "Products" }
}

@MainActor
func showProducts(_ products: [Product], in navigationController: UINavigationController) -> ScreenViewController<Int, Product> {
    let controller = productsScreen(products).makeViewController()
    navigationController.pushViewController(controller, animated: true)
    return controller
}

@MainActor
func updateProducts(_ products: [Product], in controller: ScreenViewController<Int, Product>) {
    controller.setItems(products, animated: true)
}
