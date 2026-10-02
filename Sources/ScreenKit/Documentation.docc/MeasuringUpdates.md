# Measure controller updates

Record controller-update intervals with shared boundaries for Instruments,
benchmark reports, and external telemetry adapters.

## Attach a sink

Pass an application-owned sink and a fixed screen label to
``Screen/telemetry(_:name:)``. This example assumes `screen` is an existing
Screen value:

```swift
let recorder = ScreenTelemetryRecorder()
let sink = ScreenTelemetryMultiplexer([
    ScreenSignpostTelemetry(),
    recorder,
])
let measuredScreen = screen.telemetry(sink, name: "catalog")
let controller = measuredScreen.makeViewController()
```

Each controller receives its own correlation ID. The controller retains its
sink, so avoid retaining the controller from sink callbacks. Sinks receive
bounded synchronous callbacks on the main actor and must defer expensive work,
network export, or flushing to application-owned infrastructure.

## Understand the boundary

``ScreenTelemetryPhase/update`` ends after native snapshot application,
managed supplementary updates, and the final collection layout pass, before
the caller's completion closure. It measures an update that has settled in
the controller, not a frame presented by the display.

The initial interval begins after the collection and data source are constructed.
Animated snapshot application includes animation duration. Queue wait, observed
state reread, identity validation, preparation, native apply, supplementary
updates, and layout are separate phases. Enclosing and nested intervals must
not be added together.

Counts describe actual renderer-factory/cell-provider calls during the update
and IDs requested for reload/reconfigure. SwiftUI work outside the interval,
allocations, and individual state mutations are not inferred from those counts.
Coalescing produces one measured update for one scheduled application.

## Preserve clock and outcome information

``ScreenTelemetryTimestamp`` supplies wall time for trace correlation and
monotonic time for durations. Keep the source timestamps when exporting events.
Cancelled, rejected, and unavailable-state updates have terminal outcomes and
must be distinguished from completed updates in benchmark statistics.

The recorder's events are Codable. Check
``ScreenTelemetryRecorder/droppedEventCount`` before treating a raw report as
complete. A recording that overflows its capacity is incomplete.

## Integrate an external backend

Implement ``ScreenTelemetrySink`` to translate source events. ScreenKit does
not configure a global SDK or exporter. The independent
[OpenTelemetry prototype](https://github.com/SoundBlaster/ScreenKit-Examples/tree/codex/ui-telemetry-prototype/Packages/ScreenKitOpenTelemetry)
demonstrates explicit-parent spans, seconds histograms, causal links, and
metrics that remain available when trace sampling is disabled.

The full boundary and measurement contract is documented in
[TELEMETRY.md](https://github.com/SoundBlaster/ScreenKit/blob/codex/ui-telemetry/TELEMETRY.md).

## See Also

- ``ScreenTelemetrySink``
- ``ScreenTelemetryEvent``
- ``ScreenSignpostTelemetry``
- ``ScreenTelemetryRecorder``
