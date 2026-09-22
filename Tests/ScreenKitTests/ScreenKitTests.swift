#if canImport(UIKit)
import Observation
import XCTest
import ScreenKit

@MainActor
final class ScreenKitTests: XCTestCase {
    struct Item: Identifiable, Sendable {
        let id: Int
    }

    struct StableItem: StableIdentifiable, Sendable {
        let stableID: Int
        let id: Int
        var title: String
    }

    struct Section: ScreenSectionModel, Sendable {
        let stableID: String
        let id: String
        var items: [StableItem]
    }

    @MainActor
    @Observable
    final class State: ScreenState {
        var sections: [Section]
        var useAlternateRenderer = false

        init(sections: [Section]) {
            self.sections = sections
        }
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

    func testReactiveScreenUsesStableSectionAndItemIdentity() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "legacy-catalog", items: [StableItem(stableID: 101, id: 1, title: "One")])
        ])
        let screen = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }

        let controller = screen.makeViewController()

        XCTAssertEqual(controller.sectionIDs, ["catalog"])
        XCTAssertEqual(controller.itemIDs, [101])

        let update = expectation(description: "state mutation updates the snapshot")
        state.sections[0].items.append(StableItem(stableID: 102, id: 2, title: "Two"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(controller.sectionIDs, ["catalog"])
            XCTAssertEqual(controller.itemIDs(in: "catalog"), [101, 102])
            update.fulfill()
        }
        await fulfillment(of: [update], timeout: 1)
    }

    func testReactiveRendererFactoryReadsAreTracked() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        var normalFactoryCalls = 0
        var alternateFactoryCalls = 0
        let screen = #screen(state) { _ in
            if state.useAlternateRenderer {
                alternateFactoryCalls += 1
            } else {
                normalFactoryCalls += 1
            }
            return ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }
        let controller = screen.makeViewController()
        _ = controller.itemIDs

        XCTAssertEqual(normalFactoryCalls, 1)
        XCTAssertEqual(alternateFactoryCalls, 0)

        let update = expectation(description: "renderer factory observes state")
        state.useAlternateRenderer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThan(alternateFactoryCalls, 0)
            update.fulfill()
        }
        await fulfillment(of: [update], timeout: 1)
    }

    func testReactiveControllersObserveSharedStateIndependently() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        let first = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }.makeViewController()
        let second = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }.makeViewController()
        _ = first.itemIDs
        _ = second.itemIDs

        let update = expectation(description: "both controllers observe the mutation")
        state.sections.append(Section(stableID: "recent", id: "recent", items: []))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(first.sectionIDs, ["catalog", "recent"])
            XCTAssertEqual(second.sectionIDs, ["catalog", "recent"])
            update.fulfill()
        }
        await fulfillment(of: [update], timeout: 1)
    }

    func testReactiveControllerDoesNotRetainState() {
        weak var weakState: State?
        var controller: ScreenViewController<String, StableItem>?
        do {
            let state = State(sections: [
                Section(stableID: "catalog", id: "catalog", items: [])
            ])
            weakState = state
            controller = #screen(state) { _ in
                ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
            }.makeViewController()
        }
        XCTAssertNotNil(controller)
        controller = nil
        XCTAssertNil(weakState)
    }
}
#endif
