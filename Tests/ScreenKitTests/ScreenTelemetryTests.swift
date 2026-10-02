import Foundation
import XCTest
@testable import ScreenKit
#if canImport(UIKit)
import Observation
import UIKit
#endif

final class ScreenTelemetryContractTests: XCTestCase {
    func testDurationUsesMonotonicTimeAndRejectsReversedSamples() throws {
        let start = ScreenTelemetryTimestamp(date: Date(timeIntervalSince1970: 100), uptimeNanoseconds: 10)
        let end = ScreenTelemetryTimestamp(date: Date(timeIntervalSince1970: 1), uptimeNanoseconds: 1_000_000_010)
        XCTAssertEqual(end.elapsedSeconds(since: start), 1)
        XCTAssertNil(start.elapsedSeconds(since: end))
    }

    @MainActor
    func testFanOutPreservesEventsAndRecorderReportsOverflow() async throws {
        let first = ScreenTelemetryRecorder(capacity: 1)
        let second = ScreenTelemetryRecorder()
        let sink = ScreenTelemetryMultiplexer([first, second])
        let interval = ScreenTelemetryInterval(
            updateID: UUID(), screenID: UUID(), screenName: "catalog",
            kind: .content, phase: .update, animated: false, start: .now()
        )
        sink.record(.began(interval))
        sink.record(.ended(interval, at: .now(), outcome: .completed, counts: .init()))
        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(first.droppedEventCount, 1)
        XCTAssertEqual(second.events.count, 2)
        let data = try JSONEncoder().encode(second.events)
        let decoded = try JSONDecoder().decode([ScreenTelemetryEvent].self, from: data)
        guard case let .began(restored) = decoded.first else { return XCTFail("Missing interval") }
        XCTAssertEqual(restored.id, interval.id)
        XCTAssertEqual(restored.start, interval.start)
    }
}

#if canImport(UIKit)
@MainActor
final class ScreenTelemetryLifecycleTests: XCTestCase {
    struct Item: StableIdentifiable {
        typealias ID = Int
        let stableID: Int
        var title: String
    }
    struct TestSection: ScreenSectionModel {
        typealias ID = Int
        let stableID: Int
        var items: [Item]
    }
    @Observable final class State: ScreenState {
        typealias Section = TestSection
        var sections = [TestSection(stableID: 0, items: [Item(stableID: 1, title: "First")])]
    }
    final class Probe: ScreenTelemetrySink {
        let recorder = ScreenTelemetryRecorder()
        var onEvent: ((ScreenTelemetryEvent) -> Void)?
        func record(_ event: ScreenTelemetryEvent) {
            recorder.record(event)
            onEvent?(event)
        }
    }

    private func renderer() -> ScreenCellRenderer<Item> {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            cell.contentConfiguration = content
        }
        return ScreenCellRenderer { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
    }

    func testCompletedUpdateHasBalancedPhasesAndEndsBeforeClientCompletion() async throws {
        let recorder = ScreenTelemetryRecorder()
        let renderer = renderer()
        let screen = Screen([Item(stableID: 1, title: "Old")]) { _ in renderer }.telemetry(recorder, name: "catalog")
        let controller = screen.makeViewController()
        controller.loadViewIfNeeded()
        let completed = expectation(description: "Explicit snapshot completed")
        controller.setItems([Item(stableID: 1, title: "New"), Item(stableID: 2, title: "Added")], animated: false) {
            XCTAssertEqual(self.ends(recorder.events, kind: .sections).count, 1)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
        try assertBalanced(recorder.events)
        let update = try XCTUnwrap(ends(recorder.events, kind: .sections).first)
        XCTAssertEqual(update.counts?.rendererFactoryCalls, 2)
        XCTAssertEqual(update.counts?.reconfiguredItems, 1)
        XCTAssertEqual(update.counts?.items, 2)
        let phases = recorder.events.compactMap { event -> ScreenTelemetryPhase? in
            guard case let .began(interval) = event, interval.updateID == update.interval.updateID else { return nil }
            return interval.phase
        }
        XCTAssertEqual(phases, [.update, .identityValidation, .queueWait, .snapshotPrepare, .snapshotApply, .supplementary, .layout])
    }

    func testStateBurstProducesOneMeasuredUpdatePerController() async throws {
        let state = State()
        let probe = Probe()
        let renderer = renderer()
        let screen = Screen(state) { _ in renderer }.telemetry(probe, name: "catalog")
        let first = screen.makeViewController()
        let second = screen.makeViewController()
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()
        let completed = expectation(description: "Each controller applied the state burst")
        completed.expectedFulfillmentCount = 2
        probe.onEvent = { event in
            if case let .ended(interval, _, .completed, _) = event, interval.phase == .update, interval.kind == .state {
                completed.fulfill()
            }
        }
        for revision in 0..<100 { state.sections[0].items[0].title = "Revision \(revision)" }
        await fulfillment(of: [completed], timeout: 5)
        let updates = ends(probe.recorder.events, kind: .state)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(Set(updates.map(\.interval.screenID)).count, 2)
        XCTAssertEqual(Set(updates.map(\.interval.updateID)).count, 2)
        try assertBalanced(probe.recorder.events)
        XCTAssertEqual(state.sections[0].items[0].title, "Revision 99")
    }

    func testRejectedIdentityClosesUpdateWithoutApplyingSnapshot() throws {
        let recorder = ScreenTelemetryRecorder()
        let renderer = renderer()
        var failure: String?
        let screen = Screen([Item(stableID: 1, title: "A"), Item(stableID: 1, title: "B")]) { _ in renderer }
            .telemetry(recorder, name: "catalog")
        let controller = ScreenViewController(screen: screen, identityFailureHandler: { failure = $0 })
        controller.loadViewIfNeeded()
        XCTAssertNotNil(failure)
        XCTAssertEqual(controller.itemIDs, [])
        let initial = try XCTUnwrap(ends(recorder.events, kind: .initial).first)
        XCTAssertEqual(initial.outcome, .rejected)
        XCTAssertEqual(initial.counts?.rendererFactoryCalls, 0)
        try assertBalanced(recorder.events)
    }

    func testControllerReleaseCancelsScheduledUpdateWithoutRetainingState() async throws {
        final class Owner {
            var controller: ScreenViewController<Int, Item>?
            weak var observedController: ScreenViewController<Int, Item>?
        }
        let owner = Owner()
        let state = State()
        let probe = Probe()
        let renderer = renderer()
        owner.controller = Screen(state) { _ in renderer }.telemetry(probe, name: "catalog").makeViewController()
        owner.controller?.loadViewIfNeeded()
        owner.observedController = owner.controller
        let cancelled = expectation(description: "Scheduled update cancelled on release")
        probe.onEvent = { event in
            if case let .began(interval) = event, interval.phase == .schedulingWait {
                // Release on a separate main-actor task before the scheduled read task.
                Task { @MainActor in owner.controller = nil }
            }
            if case let .ended(interval, _, .cancelled, _) = event, interval.phase == .update {
                cancelled.fulfill()
            }
        }
        state.sections[0].items[0].title = "Changed"
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertNil(owner.observedController)
        try assertBalanced(probe.recorder.events)
    }

    private typealias End = (interval: ScreenTelemetryInterval, outcome: ScreenTelemetryOutcome, counts: ScreenTelemetryCounts?)
    private func ends(_ events: [ScreenTelemetryEvent], kind: ScreenTelemetryUpdateKind) -> [End] {
        events.compactMap { event in
            guard case let .ended(interval, _, outcome, counts) = event, interval.phase == .update, interval.kind == kind else { return nil }
            return (interval, outcome, counts)
        }
    }
    private func assertBalanced(_ events: [ScreenTelemetryEvent]) throws {
        var open: Set<UUID> = []
        for event in events {
            switch event {
            case let .began(interval): XCTAssertTrue(open.insert(interval.id).inserted)
            case let .ended(interval, end, _, _):
                XCTAssertNotNil(open.remove(interval.id))
                XCTAssertNotNil(end.elapsedSeconds(since: interval.start))
            }
        }
        XCTAssertTrue(open.isEmpty)
    }
}
#endif
