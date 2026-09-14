#if canImport(UIKit)
import XCTest
@testable import ScreenKit

@MainActor
final class ScreenKitTests: XCTestCase {
    private struct Item: Identifiable, Sendable {
        let id: Int
    }

    func testScreenCreatesControllerWithoutSubclassing() {
        let screen = Screen([Item(id: 1)]) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }

        let controller = screen.makeViewController()

        XCTAssertTrue(controller is ScreenViewController<Int, Item>)
        XCTAssertEqual(controller.itemIDs, [1])
    }

    func testSectionIdentityAndItemIdentityAreExposed() {
        let screen = Screen(
            [
                ScreenSection(id: "first", items: [Item(id: 1)]),
                ScreenSection(id: "second", items: [Item(id: 2)])
            ],
            renderer: { _ in ScreenCellRenderer { _, _, _ in UICollectionViewCell() } }
        )

        let controller = screen.makeViewController()

        XCTAssertEqual(controller.sectionIDs, ["first", "second"])
        XCTAssertEqual(controller.itemIDs(in: "second"), [2])
    }
}
#endif
