#if canImport(UIKit)
import Observation
import XCTest
@testable import ScreenKit

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

    struct IntegerSection: ScreenSectionModel, Sendable {
        typealias ID = Int
        let stableID: Int
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

    @MainActor
    @Observable
    final class IntegerState: ScreenState {
        var sections: [IntegerSection]
        init(sections: [IntegerSection]) {
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

    func testReactiveSetSectionsIsIgnoredAndStateRemainsAuthoritative() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "legacy-catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        let controller = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }.makeViewController()
        XCTAssertEqual(controller.sectionIDs, ["catalog"])

        var completionCalled = false
        controller.setSections(
            [ScreenSection(id: "replacement", items: [])],
            animated: false
        ) {
            completionCalled = true
        }

        XCTAssertEqual(controller.sectionIDs, ["catalog"])
        XCTAssertFalse(completionCalled)

        state.sections.append(Section(stableID: "recent", id: "recent", items: []))
        let didUpdate = await waitUntil {
            controller.sectionIDs == ["catalog", "recent"]
        }
        XCTAssertTrue(didUpdate)
    }

    func testReactiveSetItemsIsIgnoredAndStateRemainsAuthoritative() {
        let state = IntegerState(sections: [
            IntegerSection(stableID: 7, items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        let controller = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }.makeViewController()
        XCTAssertEqual(controller.sectionIDs, [7])
        XCTAssertEqual(controller.itemIDs, [1])

        var completionCalled = false
        controller.setItems([StableItem(stableID: 99, id: 99, title: "Ignored")], animated: false) {
            completionCalled = true
        }

        XCTAssertEqual(controller.sectionIDs, [7])
        XCTAssertEqual(controller.itemIDs, [1])
        XCTAssertFalse(completionCalled)
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

    func testSupplementaryRendererUpdatesOriginalViewContentAfterStateChanges() {
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
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let first = supplementary.view(
            in: collection,
            at: IndexPath(item: 0, section: 0),
            sectionID: "catalog"
        ) as? ProbeHeader
        XCTAssertTrue(first === header)
        XCTAssertEqual(header.renderedTitle, "One")

        state.headerTitle = "Two"
        supplementary.update(header, sectionID: "catalog")
        XCTAssertEqual(header.renderedTitle, "Two")

        state.headerTitle = "Three"
        supplementary.update(header, sectionID: "catalog")
        XCTAssertEqual(header.renderedTitle, "Three")
    }

    func testReactiveControllerDoesNotRetainStateAndKeepsLastSnapshot() {
        weak var weakState: State?
        var controller: ScreenViewController<String, StableItem>?
        do {
            let state = State(sections: [
                Section(stableID: "catalog", id: "legacy-catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
            ])
            weakState = state
            controller = #screen(state) { _ in
                ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
            }.makeViewController()
            XCTAssertEqual(controller?.sectionIDs, ["catalog"])
        }
        XCTAssertNotNil(controller)
        XCTAssertNil(weakState)
        XCTAssertEqual(controller?.sectionIDs, ["catalog"])
        XCTAssertEqual(controller?.itemIDs, [1])
    }

    func testReactiveScreenStartsEmptyIfStateIsReleasedBeforeFirstRead() {
        weak var weakState: State?
        var screen: Screen<String, StableItem>!
        do {
            let state = State(sections: [
                Section(stableID: "catalog", id: "legacy-catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
            ])
            weakState = state
            screen = #screen(state) { _ in
                ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
            }
        }

        XCTAssertNil(weakState)
        let controller = screen.makeViewController()
        XCTAssertEqual(controller.sectionIDs, [])
        XCTAssertEqual(controller.itemIDs, [])
    }
}
#endif
