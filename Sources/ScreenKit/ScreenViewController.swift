#if canImport(UIKit)
import Observation
import UIKit

@MainActor
private protocol StateUpdateScheduling: AnyObject {
    func scheduleStateUpdate()
}

private final class StateUpdateRelay: @unchecked Sendable {
    weak var controller: (any StateUpdateScheduling)?

    func signal() {
        Task { @MainActor [weak self] in
            self?.controller?.scheduleStateUpdate()
        }
    }
}

/// Owns exactly one collection, data source, and snapshot lifecycle.
@MainActor
public final class ScreenViewController<SectionID: Hashable & Sendable, Item: Identifiable>: UIViewController, StateUpdateScheduling where Item.ID: Sendable {
    public private(set) var collectionView: UICollectionView!
    private var initialSections: [ScreenSection<SectionID, Item>]?
    private let stateReader: (@MainActor () -> [ScreenSection<SectionID, Item>])?
    private let renderer: (Item) -> ScreenCellRenderer<Item>
    private let itemIDProvider: (Item) -> Item.ID
    private let titleProvider: () -> String
    private let sectionProvider: ((SectionID, NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection)?
    private let supplementaryRenderers: [String: ScreenSupplementaryRenderer<SectionID>]
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, Item.ID>!
    private var itemsByID: [Item.ID: Item] = [:]
    private var renderersByID: [Item.ID: ScreenCellRenderer<Item>] = [:]

    private enum Update {
        case sections([ScreenSection<SectionID, Item>], animated: Bool)
        case content
        case supplementary
    }

    private struct Request {
        let update: Update
        let completion: (@MainActor () -> Void)?
    }

    private var pendingUpdates: [Request] = []
    private var isApplyingUpdate = false
    private var isDrainingUpdates = false
    private var isStateUpdateScheduled = false
    private let stateUpdateRelay: StateUpdateRelay?

    internal init(screen: Screen<SectionID, Item>) {
        initialSections = screen.sections
        stateReader = screen.stateReader
        stateUpdateRelay = screen.stateReader == nil ? nil : StateUpdateRelay()
        renderer = screen.renderer
        itemIDProvider = screen.itemIDProvider ?? { $0.id }
        titleProvider = screen.titleProvider
        sectionProvider = screen.sectionProvider
        supplementaryRenderers = Dictionary(uniqueKeysWithValues: screen.supplementaryRenderers.map { ($0.elementKind, $0) })
        super.init(nibName: nil, bundle: nil)
        stateUpdateRelay?.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use Screen.makeViewController()") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, let id = sectionID(at: index) else { return nil }
            let makeLayout = {
                self.sectionProvider?(id, environment)
                    ?? .list(using: .init(appearance: .insetGrouped), layoutEnvironment: environment)
            }
            guard stateReader != nil else { return makeLayout() }
            let relay = stateUpdateRelay
            return withObservationTracking(makeLayout) {
                relay?.signal()
            }
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.accessibilityIdentifier = "screen.collection"
        collectionView.keyboardDismissMode = .interactive
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            // UIKit animates this guide with the docked keyboard, keeping editable
            // content reachable without app-level keyboard notifications or inset math.
            collectionView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collection, indexPath, id in
            guard let self, let item = itemsByID[id], let renderer = renderersByID[id] else { return nil }
            guard stateReader != nil else {
                return renderer.cell(in: collection, at: indexPath, item: item)
            }
            let relay = stateUpdateRelay
            return withObservationTracking {
                renderer.cell(in: collection, at: indexPath, item: item)
            } onChange: {
                relay?.signal()
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] collection, kind, indexPath in
            guard let self, let id = sectionID(at: indexPath.section) else { return nil }
            return makeSupplementaryView(
                in: collection,
                kind: kind,
                at: indexPath,
                sectionID: id
            )
        }
        title = titleProvider()
        let sections = stateReader != nil ? readObservedState() : (initialSections ?? [])
        initialSections = nil
        setSections(sections, animated: false)
    }

    private func readObservedState() -> [ScreenSection<SectionID, Item>] {
        guard let stateReader else { return [] }
        let relay = stateUpdateRelay
        return withObservationTracking {
            _ = titleProvider()
            return stateReader()
        } onChange: {
            relay?.signal()
        }
    }

    fileprivate func scheduleStateUpdate() {
        guard stateReader != nil, !isStateUpdateScheduled else { return }
        isStateUpdateScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isStateUpdateScheduled = false
            setSections(readObservedState(), animated: true)
        }
    }

    @available(iOS 26.0, *)
    public override func updateProperties() {
        super.updateProperties()
        title = titleProvider()
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if #unavailable(iOS 26.0) { title = titleProvider() }
    }

    public var itemIDs: [Item.ID] {
        loadViewIfNeeded()
        return dataSource.snapshot().itemIdentifiers
    }

    public var sectionIDs: [SectionID] {
        loadViewIfNeeded()
        return dataSource.snapshot().sectionIdentifiers
    }

    public func itemIDs(in section: SectionID) -> [Item.ID] {
        loadViewIfNeeded()
        let snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(section) else { return [] }
        return snapshot.itemIdentifiers(inSection: section)
    }

    private func sectionID(at index: Int) -> SectionID? {
        guard let ids = dataSource?.snapshot().sectionIdentifiers, ids.indices.contains(index) else { return nil }
        return ids[index]
    }

    /// Requests are applied FIFO, including calls made during animations or completions.
    /// Item IDs must be globally unique across sections. Completion follows native apply
    /// and a collection layout pass. Releasing the controller abandons pending completions.
    public func setSections(
        _ sections: [ScreenSection<SectionID, Item>],
        animated: Bool = true,
        completion: (@MainActor () -> Void)? = nil
    ) {
        let sectionIDs = sections.map(\.id)
        precondition(Set(sectionIDs).count == sectionIDs.count, "Screen section IDs must be unique")
        let ids = sections.flatMap { $0.items.map(itemIDProvider) }
        precondition(Set(ids).count == ids.count, "Screen item IDs must be globally unique")
        enqueue(.sections(sections, animated: animated), completion: completion)
    }

    /// Explicit refresh for items, title, and managed visible headers/footers.
    /// Queues behind pending snapshots; it never reapplies an outdated snapshot.
    public func refreshContent(completion: (@MainActor () -> Void)? = nil) {
        enqueue(.content, completion: completion)
    }

    /// Updates existing supplementary views in place. Newly visible views use the same updater.
    public func refreshSupplementaryContent(completion: (@MainActor () -> Void)? = nil) {
        enqueue(.supplementary, completion: completion)
    }

    private func enqueue(_ update: Update, completion: (@MainActor () -> Void)?) {
        loadViewIfNeeded()
        pendingUpdates.append(Request(update: update, completion: completion))
        drainUpdates()
    }

    private func drainUpdates() {
        guard !isDrainingUpdates else { return }
        isDrainingUpdates = true
        defer { isDrainingUpdates = false }
        // UIKit can complete nonanimated applies synchronously. Drain those requests
        // in a loop so reentrant completions never grow the call stack per request.
        while !isApplyingUpdate, !pendingUpdates.isEmpty {
            isApplyingUpdate = true
            let request = pendingUpdates.removeFirst()
            switch request.update {
            case let .sections(sections, animated):
                applySections(sections, animated: animated) { [weak self] in self?.finish(request) }
            case .content:
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems(snapshot.itemIdentifiers)
                dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                    guard let self else { return }
                    title = titleProvider()
                    updateVisibleSupplementaries()
                    finish(request)
                }
            case .supplementary:
                updateVisibleSupplementaries()
                finish(request)
            }
        }
    }

    private func applySections(
        _ sections: [ScreenSection<SectionID, Item>],
        animated: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        let items = sections.flatMap(\.items)
        let ids = items.map(itemIDProvider)
        let previous = renderersByID
        let nextItems = Dictionary(uniqueKeysWithValues: items.map { (self.itemIDProvider($0), $0) })
        let makeRenderers = {
            Dictionary(uniqueKeysWithValues: items.map { (self.itemIDProvider($0), self.renderer($0)) })
        }
        let nextRenderers: [Item.ID: ScreenCellRenderer<Item>]
        if stateReader != nil {
            let relay = stateUpdateRelay
            nextRenderers = withObservationTracking(makeRenderers) {
                relay?.signal()
            }
        } else {
            nextRenderers = makeRenderers()
        }
        // Outgoing cells may still be requested during an animated transition.
        // Keep their payloads/renderers until UIKit completes this snapshot.
        itemsByID.merge(nextItems) { _, new in new }
        renderersByID.merge(nextRenderers) { _, new in new }
        var snapshot = NSDiffableDataSourceSnapshot<SectionID, Item.ID>()
        for section in sections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.items.map(itemIDProvider), toSection: section.id)
        }
        let retained = ids.filter { previous[$0] != nil }
        let replaced = retained.filter { previous[$0]?.identity != nextRenderers[$0]?.identity }
        let replacedSet = Set(replaced)
        snapshot.reloadItems(replaced)
        snapshot.reconfigureItems(retained.filter { !replacedSet.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            itemsByID = nextItems
            renderersByID = nextRenderers
            title = titleProvider()
            updateVisibleSupplementaries()
            completion()
        }
    }

    private func makeSupplementaryView(
        in collection: UICollectionView,
        kind: String,
        at indexPath: IndexPath,
        sectionID: SectionID
    ) -> UICollectionReusableView? {
        guard let renderer = supplementaryRenderers[kind] else { return nil }
        guard stateReader != nil else {
            return renderer.view(in: collection, at: indexPath, sectionID: sectionID)
        }
        let relay = stateUpdateRelay
        return withObservationTracking {
            renderer.view(in: collection, at: indexPath, sectionID: sectionID)
        } onChange: {
            relay?.signal()
        }
    }

    private func updateVisibleSupplementaries() {
        for (kind, renderer) in supplementaryRenderers {
            for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
                guard let id = sectionID(at: indexPath.section),
                      let view = collectionView.supplementaryView(forElementKind: kind, at: indexPath) else { continue }
                if stateReader != nil {
                    let relay = stateUpdateRelay
                    withObservationTracking {
                        renderer.update(view, sectionID: id)
                    } onChange: {
                        relay?.signal()
                    }
                } else {
                    renderer.update(view, sectionID: id)
                }
                view.setNeedsLayout()
            }
        }
    }

    private func finish(_ request: Request) {
        invalidateLayout()
        collectionView.layoutIfNeeded()
        // Keep the queue locked while user code runs: reentrant requests append after
        // requests already queued, and cannot overwrite the current transition's maps.
        request.completion?()
        isApplyingUpdate = false
        drainUpdates()
    }

    public func invalidateLayout() {
        loadViewIfNeeded()
        collectionView.collectionViewLayout.invalidateLayout()
    }
}

extension ScreenViewController where SectionID == Int {
    /// Replaces the entire screen with its single default section.
    public func setItems(
        _ items: [Item],
        animated: Bool = true,
        completion: (@MainActor () -> Void)? = nil
    ) {
        setSections([ScreenSection(id: 0, items: items)], animated: animated, completion: completion)
    }
}
#endif
