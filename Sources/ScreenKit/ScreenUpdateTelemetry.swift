#if canImport(UIKit)
import Foundation

@MainActor
internal struct ScreenTelemetryConfiguration {
    let name: String
    let sink: any ScreenTelemetrySink
}

/// The controller alone owns this registry. Its nonisolated finalizer snapshots
/// Sendable sessions and defers sink delivery to the main actor, avoiding the
/// isolated-deinit back-deployment path on older iOS runtimes.
@MainActor
internal final class ScreenTelemetryLifetime {
    private let configuration: ScreenTelemetryConfiguration
    private let screenID = UUID()
    private var updates: [UUID: ScreenUpdateTelemetry] = [:]

    init(configuration: ScreenTelemetryConfiguration) {
        self.configuration = configuration
    }

    func make(_ kind: ScreenTelemetryUpdateKind, animated: Bool) -> ScreenUpdateTelemetry {
        let update = ScreenUpdateTelemetry(
            configuration: configuration, screenID: screenID, kind: kind, animated: animated,
            onFinish: { [weak self] id in self?.updates.removeValue(forKey: id) }
        )
        updates[update.updateID] = update
        return update
    }

    deinit {
        let pending = Array(updates.values)
        guard !pending.isEmpty else { return }
        let releasedAt = ScreenTelemetryTimestamp.now()
        Task { @MainActor in
            for update in pending { update.finish(.cancelled, at: releasedAt) }
        }
    }
}

@MainActor
internal final class ScreenUpdateTelemetry {
    let updateID = UUID()
    var counts = ScreenTelemetryCounts()
    private let configuration: ScreenTelemetryConfiguration
    private let screenID: UUID
    private let kind: ScreenTelemetryUpdateKind
    private let animated: Bool
    private let onFinish: @MainActor (UUID) -> Void
    private var intervals: [ScreenTelemetryPhase: ScreenTelemetryInterval] = [:]
    private var isFinished = false

    init(
        configuration: ScreenTelemetryConfiguration, screenID: UUID,
        kind: ScreenTelemetryUpdateKind, animated: Bool,
        onFinish: @escaping @MainActor (UUID) -> Void
    ) {
        self.configuration = configuration
        self.screenID = screenID
        self.kind = kind
        self.animated = animated
        self.onFinish = onFinish
        begin(.update)
    }

    func begin(_ phase: ScreenTelemetryPhase) {
        guard !isFinished, intervals[phase] == nil else { return }
        let interval = ScreenTelemetryInterval(
            updateID: updateID, screenID: screenID, screenName: configuration.name,
            kind: kind, phase: phase, animated: animated, start: .now()
        )
        intervals[phase] = interval
        configuration.sink.record(.began(interval))
    }

    func end(
        _ phase: ScreenTelemetryPhase, outcome: ScreenTelemetryOutcome = .completed,
        at timestamp: ScreenTelemetryTimestamp? = nil
    ) {
        guard let interval = intervals.removeValue(forKey: phase) else { return }
        configuration.sink.record(.ended(interval, at: timestamp ?? .now(), outcome: outcome, counts: phase == .update ? counts : nil))
    }

    func finish(_ outcome: ScreenTelemetryOutcome = .completed, at timestamp: ScreenTelemetryTimestamp? = nil) {
        guard !isFinished else { return }
        isFinished = true
        let finishedAt = timestamp ?? .now()
        for phase in ScreenTelemetryPhase.allCases where phase != .update { end(phase, outcome: outcome, at: finishedAt) }
        end(.update, outcome: outcome, at: finishedAt)
        onFinish(updateID)
    }
}
#endif
