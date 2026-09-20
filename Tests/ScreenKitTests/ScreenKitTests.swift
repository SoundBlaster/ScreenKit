#if canImport(UIKit)
import XCTest
import ScreenKit

@MainActor
final class ScreenKitTests: XCTestCase {
    private struct Item: Identifiable, Sendable {
        let id: Int
    }

    func testScreenCreatesControllerWithoutSubclassing() {
        let screen = #screen([Item(id: 1)]) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }
        .title { "Macro screen" }

        let controller = screen.makeViewController()

        XCTAssertEqual(
            ObjectIdentifier(type(of: controller)),
            ObjectIdentifier(ScreenViewController<Int, Item>.self)
        )
        XCTAssertEqual(controller.itemIDs, [1])
    }

    func testSectionIdentityAndItemIdentityAreExposed() {
        let sections: [ScreenSection<String, Item>] = [
            ScreenSection(id: "first", items: [Item(id: 1)]),
            ScreenSection(id: "second", items: [Item(id: 2)])
        ]
        let screen = Screen<String, Item>(
            sections,
            renderer: { _ in ScreenCellRenderer { _, _, _ in UICollectionViewCell() } }
        )

        let controller = screen.makeViewController()

        XCTAssertEqual(controller.sectionIDs, ["first", "second"])
        XCTAssertEqual(controller.itemIDs(in: "second"), [2])
    }
}
#endif
