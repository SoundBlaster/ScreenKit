#if canImport(UIKit)
import Observation
import XCTest
import ScreenKit

@MainActor
final class ScreenKitTests: XCTestCase {
    final class ProbeCell: UICollectionViewCell {
        var renderedTitle = ""
    }

    final class ProbeHeader: UICollectionReusableView {
        var renderedTitle = ""
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return predicate()
    }

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
        var headerTitle = "One"
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

        state.sections[0].items.append(StableItem(stableID: 102, id: 2, title: "Two"))
        let didUpdate = await waitUntil {
            controller.itemIDs(in: "catalog") == [101, 102]
        }
        XCTAssertTrue(didUpdate)
        XCTAssertEqual(controller.sectionIDs, ["catalog"])
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

        state.useAlternateRenderer = true
        let didUpdate = await waitUntil { alternateFactoryCalls > 0 }
        XCTAssertTrue(didUpdate)
    }

    func testReactiveRendererUpdatesRenderedCellContent() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        let screen = #screen(state) { item in
            let title = state.useAlternateRenderer ? "Alternate" : item.title
            return ScreenCellRenderer { _, _, _ in
                let cell = ProbeCell()
                cell.renderedTitle = title
                return cell
            }
        }
        let controller = screen.makeViewController()
        _ = controller.itemIDs
        let indexPath = IndexPath(item: 0, section: 0)
        let initialCell = controller.collectionView.dataSource?.collectionView(
            controller.collectionView,
            cellForItemAt: indexPath
        ) as? ProbeCell
        XCTAssertEqual(initialCell?.renderedTitle, "One")

        state.useAlternateRenderer = true
        let didUpdate = await waitUntil {
            let updatedCell = controller.collectionView.dataSource?.collectionView(
                controller.collectionView,
                cellForItemAt: indexPath
            ) as? ProbeCell
            return updatedCell?.renderedTitle == "Alternate"
        }
        XCTAssertTrue(didUpdate)
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

        state.sections.append(Section(stableID: "recent", id: "recent", items: []))
        let didUpdate = await waitUntil {
            first.sectionIDs == ["catalog", "recent"]
                && second.sectionIDs == ["catalog", "recent"]
        }
        XCTAssertTrue(didUpdate)
    }

    func testReactiveUpdatesCoalesceStateMutations() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        var factoryCalls = 0
        let screen = #screen(state) { _ in
            factoryCalls += 1
            return ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }
        let controller = screen.makeViewController()
        _ = controller.itemIDs
        XCTAssertEqual(factoryCalls, 1)

        state.sections[0].items[0].title = "Updated"
        state.useAlternateRenderer = true

        let didUpdate = await waitUntil { factoryCalls == 2 }
        XCTAssertTrue(didUpdate)
        XCTAssertEqual(factoryCalls, 2)
    }

    func testReactiveSupplementaryRendererUpdatesContentAfterStateChanges() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        let header = ProbeHeader()
        let supplementary = ScreenSupplementaryRenderer<String>(
            elementKind: UICollectionView.elementKindSectionHeader,
            make: { _, _ in header },
            update: { (view: ProbeHeader, _) in
                view.renderedTitle = state.headerTitle
            }
        )
        let screen = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }
        .supplementary([supplementary])
        let controller = screen.makeViewController()
        _ = controller.sectionIDs

        let first = controller.collectionView.dataSource?.collectionView?(
            controller.collectionView,
            viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) as? ProbeHeader
        XCTAssertEqual(first?.renderedTitle, "One")

        state.headerTitle = "Two"
        controller.refreshSupplementaryContent()
        let didUpdate = await waitUntil {
            let updated = controller.collectionView.dataSource?.collectionView?(
                controller.collectionView,
                viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? ProbeHeader
            return updated?.renderedTitle == "Two"
        }
        XCTAssertTrue(didUpdate)

        state.headerTitle = "Three"
        controller.refreshSupplementaryContent()
        let didUpdateAgain = await waitUntil {
            let updated = controller.collectionView.dataSource?.collectionView?(
                controller.collectionView,
                viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? ProbeHeader
            return updated?.renderedTitle == "Three"
        }
        XCTAssertTrue(didUpdateAgain)
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
            _ = controller?.itemIDs
        }
        XCTAssertNotNil(controller)
        controller = nil
        XCTAssertNil(weakState)
    }
}
#endif
