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

    private func show(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        controller.loadViewIfNeeded()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        if let controller = controller as? ScreenViewController<String, StableItem> {
            controller.collectionView.layoutIfNeeded()
        }
        return window
    }

    struct Item: Identifiable, Sendable {
        let id: Int
    }

    struct StableItem: StableIdentifiable, Sendable {
        let stableID: Int
        let id: Int
        var title: String
    }

    struct StableOnlyItem: StableIdentifiable, Sendable {
        typealias ID = UUID
        let stableID: ID
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

    struct StableOnlySection: ScreenSectionModel, Sendable {
        typealias ID = UUID
        let stableID: ID
        var items: [StableOnlyItem]
    }

    @MainActor
    @Observable
    final class State: ScreenState {
        var sections: [Section]
        var headerTitle = "One"
        var useAlternateRenderer = false
        var layoutColumns = 1
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

    func testStableIdentifiableCanDefineOnlyStableIDAndExplicitIDType() {
        let itemID = UUID()
        let sectionID = UUID()
        let item = StableOnlyItem(stableID: itemID)
        let section = StableOnlySection(stableID: sectionID, items: [item])

        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(section.id, sectionID)
    }

    func testReactiveSectionsAndItemsCanBeReorderedRemovedAndMoved() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "legacy-catalog", items: [
                StableItem(stableID: 1, id: 101, title: "One"),
                StableItem(stableID: 2, id: 102, title: "Two")
            ]),
            Section(stableID: "recent", id: "legacy-recent", items: [
                StableItem(stableID: 3, id: 103, title: "Three")
            ])
        ])
        let controller = #screen(state) { _ in
            ScreenCellRenderer { _, _, _ in UICollectionViewCell() }
        }.makeViewController()
        _ = controller.itemIDs

        state.sections.reverse()
        let reorderedSections = await waitUntil { controller.sectionIDs == ["recent", "catalog"] }
        XCTAssertTrue(reorderedSections)

        state.sections[1].items.reverse()
        let reorderedItems = await waitUntil { controller.itemIDs(in: "catalog") == [2, 1] }
        XCTAssertTrue(reorderedItems)

        let movedItem = state.sections[1].items.removeFirst()
        state.sections[0].items.append(movedItem)
        let moveWasApplied = await waitUntil {
            controller.itemIDs(in: "recent") == [3, 2]
                && controller.itemIDs(in: "catalog") == [1]
        }
        XCTAssertTrue(moveWasApplied)

        state.sections[0].items.removeAll { $0.stableID == 3 }
        let standaloneRemoval = await waitUntil { controller.itemIDs(in: "recent") == [2] }
        XCTAssertTrue(standaloneRemoval)

        state.sections.removeAll { $0.stableID == "catalog" }
        let removedSection = await waitUntil { controller.sectionIDs == ["recent"] }
        XCTAssertTrue(removedSection)
        XCTAssertEqual(controller.itemIDs, [2])
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

    func testReactiveItemContentChangeUpdatesVisibleCellWithStableIdentity() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 9001, title: "One")])
        ])
        let registration = UICollectionView.CellRegistration<ProbeCell, StableItem> { cell, _, item in
            cell.renderedTitle = item.title
        }
        let screen = #screen(state) { _ in
            ScreenCellRenderer { collection, indexPath, item in
                collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
            }
        }
        let controller = screen.makeViewController()
        let window = show(controller)
        let collection = controller.collectionView!
        let indexPath = IndexPath(item: 0, section: 0)
        let cellAppeared = await waitUntil { collection.cellForItem(at: indexPath) is ProbeCell }
        XCTAssertTrue(cellAppeared)
        let visibleCell = collection.cellForItem(at: indexPath) as? ProbeCell
        XCTAssertEqual(visibleCell?.renderedTitle, "One")

        var updatedSection = state.sections[0]
        updatedSection.items[0].title = "Updated"
        state.sections = [updatedSection]
        let cellUpdated = await waitUntil {
            (collection.cellForItem(at: indexPath) as? ProbeCell)?.renderedTitle == "Updated"
        }
        XCTAssertTrue(cellUpdated)
        XCTAssertEqual(controller.itemIDs, [1])
        withExtendedLifetime(window) {}
    }

    func testReactiveLayoutProviderTracksStateOnIOS18Fallback() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        var observedColumnCounts: [Int] = []
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, StableItem> { _, _, _ in }
        let screen = #screen(state) { _ in
            ScreenCellRenderer { collection, indexPath, item in
                collection.dequeueConfiguredReusableCell(
                    using: cellRegistration,
                    for: indexPath,
                    item: item
                )
            }
        }
        .layout { _, _ in
            let columns = state.layoutColumns
            observedColumnCounts.append(columns)
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                heightDimension: .absolute(44)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
            return NSCollectionLayoutSection(group: group)
        }
        let controller = screen.makeViewController()
        let window = show(controller)
        let initialLayoutObserved = await waitUntil { observedColumnCounts.contains(1) }
        XCTAssertTrue(initialLayoutObserved)
        let previousCount = observedColumnCounts.count

        state.layoutColumns = 2
        let updatedLayoutObserved = await waitUntil {
            observedColumnCounts.count > previousCount && observedColumnCounts.last == 2
        }
        XCTAssertTrue(updatedLayoutObserved)
        withExtendedLifetime(window) {}
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

    func testReactiveSupplementaryCreationAndRepeatedUpdatesUseSameVisibleView() async {
        let state = State(sections: [
            Section(stableID: "catalog", id: "catalog", items: [StableItem(stableID: 1, id: 1, title: "One")])
        ])
        let headerKind = UICollectionView.elementKindSectionHeader
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, StableItem> { _, _, _ in }
        let renderer = ScreenSupplementaryRenderer<String>(
            elementKind: headerKind,
            make: { collection, indexPath in
                let view = collection.dequeueReusableSupplementaryView(
                    ofKind: headerKind,
                    withReuseIdentifier: "ProbeHeader",
                    for: indexPath
                ) as! ProbeHeader
                view.renderedTitle = state.headerTitle
                return view
            },
            update: { (view: ProbeHeader, _) in view.renderedTitle = state.headerTitle }
        )
        let screen = #screen(state) { _ in
            ScreenCellRenderer { collection, indexPath, item in
                collection.dequeueConfiguredReusableCell(
                    using: cellRegistration,
                    for: indexPath,
                    item: item
                )
            }
        }
        .layout { _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: itemSize,
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)),
                elementKind: headerKind,
                alignment: .top
            )]
            return section
        }
        .supplementary([renderer])
        let controller = screen.makeViewController()
        controller.loadViewIfNeeded()
        controller.collectionView.register(
            ProbeHeader.self,
            forSupplementaryViewOfKind: headerKind,
            withReuseIdentifier: "ProbeHeader"
        )
        let window = show(controller)
        let collection = controller.collectionView!
        let indexPath = IndexPath(item: 0, section: 0)
        let created = await waitUntil {
            collection.supplementaryView(forElementKind: headerKind, at: indexPath) is ProbeHeader
        }
        XCTAssertTrue(created)
        let header = collection.supplementaryView(forElementKind: headerKind, at: indexPath) as? ProbeHeader
        XCTAssertEqual(header?.renderedTitle, "One")

        state.headerTitle = "Two"
        let firstUpdateObserved = await waitUntil { header?.renderedTitle == "Two" }
        XCTAssertTrue(firstUpdateObserved)
        XCTAssertTrue(collection.supplementaryView(forElementKind: headerKind, at: indexPath) === header)

        state.headerTitle = "Three"
        let secondUpdateObserved = await waitUntil { header?.renderedTitle == "Three" }
        XCTAssertTrue(secondUpdateObserved)
        XCTAssertTrue(collection.supplementaryView(forElementKind: headerKind, at: indexPath) === header)
        withExtendedLifetime(window) {}
    }

    func testDuplicateIDsAreReportedThroughControllerBeforeSnapshotEnqueue() {
        var messages: [String] = []
        let screen = Screen<String, Item>(
            [ScreenSection(id: "kept", items: [Item(id: 1)])],
            renderer: { _ in ScreenCellRenderer { _, _, _ in UICollectionViewCell() } }
        )
        let controller = ScreenViewController(screen: screen) { messages.append($0) }
        XCTAssertEqual(controller.sectionIDs, ["kept"])
        XCTAssertEqual(controller.itemIDs, [1])

        controller.setSections([
            ScreenSection(id: "duplicate", items: []),
            ScreenSection(id: "duplicate", items: [])
        ], animated: false)
        XCTAssertEqual(
            messages,
            ["Screen section IDs must be unique; duplicate at sections[0] and sections[1]."]
        )
        XCTAssertEqual(controller.sectionIDs, ["kept"])
        XCTAssertEqual(controller.itemIDs, [1])

        controller.setSections([
            ScreenSection(id: "first", items: [Item(id: 2)]),
            ScreenSection(id: "second", items: [Item(id: 2)])
        ], animated: false)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(
            messages.last,
            "Screen item IDs must be globally unique; duplicate at sections[0].items[0] and sections[1].items[0]."
        )
        XCTAssertEqual(controller.sectionIDs, ["kept"])
        XCTAssertEqual(controller.itemIDs, [1])
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
