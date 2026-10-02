#if canImport(OSLog)
import Foundation
import OSLog

/// Emits stable, named intervals that Instruments and XCTest can measure.
@available(iOS 18.0, macOS 12.0, tvOS 18.0, watchOS 8.0, *)
@MainActor
public final class ScreenSignpostTelemetry: ScreenTelemetrySink {
    /// The subsystem shared by the default signposter and XCTest metrics.
    public static let subsystem = "com.soundblaster.ScreenKit"
    /// The category shared by the default signposter and XCTest metrics.
    public static let category = "UIPerformance"

    private let signposter: OSSignposter
    private var intervals: [UUID: OSSignpostIntervalState] = [:]

    /// Creates a signposter; each concurrent interval receives a distinct signpost ID.
    public init() {
        signposter = OSSignposter(subsystem: Self.subsystem, category: Self.category)
    }

    /// Emits the source boundary, retaining interval state only until its end.
    public func record(_ event: ScreenTelemetryEvent) {
        switch event {
        case let .began(interval):
            intervals[interval.id] = signposter.beginInterval(
                interval.phase.signpostName, id: signposter.makeSignpostID(),
                "\(interval.screenName, privacy: .public)"
            )
        case let .ended(interval, _, outcome, _):
            guard let state = intervals.removeValue(forKey: interval.id) else { return }
            signposter.endInterval(interval.phase.signpostName, state, "\(outcome.rawValue, privacy: .public)")
        }
    }
}

private extension ScreenTelemetryPhase {
    var signpostName: StaticString {
        switch self {
        case .update: "screenkit.update"
        case .schedulingWait: "screenkit.scheduling.wait"
        case .stateRead: "screenkit.state.read"
        case .identityValidation: "screenkit.identity.validate"
        case .queueWait: "screenkit.queue.wait"
        case .snapshotPrepare: "screenkit.snapshot.prepare"
        case .snapshotApply: "screenkit.snapshot.apply"
        case .supplementary: "screenkit.supplementary"
        case .layout: "screenkit.layout"
        }
    }
}
#endif
