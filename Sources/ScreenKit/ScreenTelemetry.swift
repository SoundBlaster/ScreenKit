import Dispatch
import Foundation

/// The cause of a controller update, independent of its rendering backend.
public enum ScreenTelemetryUpdateKind: String, Codable, Sendable {
    /// The first snapshot, after the controller creates its collection view.
    case initial
    /// A scheduled update of observable state.
    case state
    /// An explicit replacement of sections or items.
    case sections
    /// An explicit refresh of item and supplementary content.
    case content
    /// An explicit refresh of visible supplementary content.
    case supplementary
}

/// A measured part of the controller's update lifecycle.
public enum ScreenTelemetryPhase: String, Codable, Sendable, CaseIterable {
    /// The entire accepted request, through its final layout pass.
    case update
    /// Waiting for the main-actor task that rereads observable state.
    case schedulingWait
    /// Reading state and the observed title provider.
    case stateRead
    /// Checking section and item identity before enqueueing.
    case identityValidation
    /// Waiting behind earlier snapshot requests.
    case queueWait
    /// Preparing payload maps, renderers, and the diffable snapshot.
    case snapshotPrepare
    /// Native snapshot application, including its animation when enabled.
    case snapshotApply
    /// Updating managed supplementary content currently visible in the collection.
    case supplementary
    /// The final layout invalidation and synchronous layout pass.
    case layout
}

/// The terminal result of an interval or update.
public enum ScreenTelemetryOutcome: String, Codable, Sendable {
    /// The interval completed at its documented boundary.
    case completed
    /// The controller was released before its update completed.
    case cancelled
    /// Identity validation rejected the request.
    case rejected
    /// Feature-owned state was released before it could be read.
    case stateUnavailable
}

/// Wall time for trace correlation and monotonic time for durations.
public struct ScreenTelemetryTimestamp: Codable, Sendable, Equatable {
    /// The wall-clock time, used only for correlation with other traces.
    public let date: Date
    /// Monotonic nanoseconds since the system booted.
    public let uptimeNanoseconds: UInt64

    /// Creates a timestamp, including synthetic timestamps for deterministic tests.
    public init(date: Date, uptimeNanoseconds: UInt64) {
        self.date = date
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    /// Captures the clocks at the event source, before delivery to any sink.
    public static func now() -> Self {
        Self(date: Date(), uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }

    /// Returns elapsed seconds, or nil for a reversed monotonic timestamp.
    public func elapsedSeconds(since start: Self) -> Double? {
        guard uptimeNanoseconds >= start.uptimeNanoseconds else { return nil }
        return Double(uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }
}

/// An interval with stable correlation IDs and an application-supplied screen name.
public struct ScreenTelemetryInterval: Codable, Sendable {
    /// The ID of this interval, shared by its begin and end events.
    public let id: UUID
    /// The ID shared by all intervals belonging to one update.
    public let updateID: UUID
    /// The controller instance ID; suitable for trace correlation, not metric labels.
    public let screenID: UUID
    /// A fixed screen name, such as `catalog`, rather than a dynamic title.
    public let screenName: String
    /// The cause of the update.
    public let kind: ScreenTelemetryUpdateKind
    /// The part of the update measured by this interval.
    public let phase: ScreenTelemetryPhase
    /// Whether the request applies an animated snapshot.
    public let animated: Bool
    /// The source timestamp of the interval's beginning.
    public let start: ScreenTelemetryTimestamp

    /// Creates an interval for a telemetry producer or a deterministic fixture.
    public init(
        id: UUID = UUID(), updateID: UUID, screenID: UUID, screenName: String,
        kind: ScreenTelemetryUpdateKind, phase: ScreenTelemetryPhase,
        animated: Bool, start: ScreenTelemetryTimestamp
    ) {
        self.id = id
        self.updateID = updateID
        self.screenID = screenID
        self.screenName = screenName
        self.kind = kind
        self.phase = phase
        self.animated = animated
        self.start = start
    }
}

/// Actual controller work during an update, not a count of state property writes.
public struct ScreenTelemetryCounts: Codable, Sendable, Equatable {
    /// The number of sections in the requested snapshot.
    public var sections = 0
    /// The number of items in the requested snapshot.
    public var items = 0
    /// Calls to the item-to-renderer factory during snapshot preparation.
    public var rendererFactoryCalls = 0
    /// Calls to a cell renderer while this update is active.
    public var cellProviderCalls = 0
    /// Managed supplementary updates while this update is active.
    public var supplementaryUpdates = 0
    /// IDs passed to snapshot reload.
    public var reloadedItems = 0
    /// IDs passed to snapshot reconfigure; UIKit may only configure visible cells.
    public var reconfiguredItems = 0

    /// Creates zeroed counters.
    public init() {}
}

/// A typed source event shared by signposts, benchmark reports, and external adapters.
public enum ScreenTelemetryEvent: Codable, Sendable {
    /// An interval began at its source timestamp.
    case began(ScreenTelemetryInterval)
    /// An interval ended; counts are supplied only on the terminal update event.
    case ended(
        ScreenTelemetryInterval, at: ScreenTelemetryTimestamp,
        outcome: ScreenTelemetryOutcome, counts: ScreenTelemetryCounts?
    )
}

/// Receives bounded, synchronous callbacks from the main actor.
///
/// Sinks must not mutate UI or observed state, perform network I/O, or flush
/// exporters inside `record`. Queue expensive work separately and preserve
/// source timestamps. ScreenKit does not install a global provider or exporter.
@MainActor
public protocol ScreenTelemetrySink: AnyObject {
    /// Records one interval boundary without blocking the update lifecycle.
    func record(_ event: ScreenTelemetryEvent)
}

/// Forwards the same source events to multiple independently owned sinks.
@MainActor
public final class ScreenTelemetryMultiplexer: ScreenTelemetrySink {
    private let sinks: [any ScreenTelemetrySink]

    /// Creates a fan-out sink, preserving the specified delivery order.
    public init(_ sinks: [any ScreenTelemetrySink]) { self.sinks = sinks }

    /// Delivers an event to each sink without changing its timestamp or IDs.
    public func record(_ event: ScreenTelemetryEvent) {
        for sink in sinks { sink.record(event) }
    }
}

/// Retains a bounded set of raw events for offline benchmark reports.
@MainActor
public final class ScreenTelemetryRecorder: ScreenTelemetrySink {
    /// The retained events, in source order.
    public private(set) var events: [ScreenTelemetryEvent] = []
    /// Events omitted because the recording reached its configured capacity.
    public private(set) var droppedEventCount = 0
    /// The maximum number of retained events.
    public let capacity: Int

    /// Creates a bounded recorder. A report with dropped events is incomplete.
    public init(capacity: Int = 10_000) {
        precondition(capacity > 0, "Telemetry recorder capacity must be positive")
        self.capacity = capacity
    }

    /// Retains the event or increments the visible dropped-event count.
    public func record(_ event: ScreenTelemetryEvent) {
        guard events.count < capacity else { droppedEventCount += 1; return }
        events.append(event)
    }
}
