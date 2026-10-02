#if canImport(UIKit)
import Foundation

@MainActor
internal struct ScreenTelemetryConfiguration {
    let name: String
    let sink: any ScreenTelemetrySink
}

@MainActor
internal final class ScreenUpdateTelemetry {
    let updateID = UUID()
    var counts = ScreenTelemetryCounts()
    private let configuration: ScreenTelemetryConfiguration
    private let screenID: UUID
    private let kind: ScreenTelemetryUpdateKind
    private let animated: Bool
    private var intervals: [ScreenTelemetryPhase: ScreenTelemetryInterval] = [:]
    private var isFinished = false

    init(configuration: ScreenTelemetryConfiguration, screenID: UUID, kind: ScreenTelemetryUpdateKind, animated: Bool) {
        self.configuration = configuration
        self.screenID = screenID
        self.kind = kind
        self.animated = animated
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

    func end(_ phase: ScreenTelemetryPhase, outcome: ScreenTelemetryOutcome = .completed) {
        guard let interval = intervals.removeValue(forKey: phase) else { return }
        configuration.sink.record(.ended(interval, at: .now(), outcome: outcome, counts: phase == .update ? counts : nil))
    }

    func finish(_ outcome: ScreenTelemetryOutcome = .completed) {
        guard !isFinished else { return }
        isFinished = true
        for phase in ScreenTelemetryPhase.allCases where phase != .update { end(phase, outcome: outcome) }
        end(.update, outcome: outcome)
    }
}
#endif
