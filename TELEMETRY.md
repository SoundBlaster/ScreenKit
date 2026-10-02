# UI telemetry contract — version 1

ScreenKit emits opt-in, typed interval boundaries for a controller update. Apple
signposts, raw benchmark reports, and OpenTelemetry adapters consume the same
events. No dependency on OpenTelemetry is added to the ScreenKit package.

## Scope and ownership

Attach a sink with `Screen.telemetry(_:name:)`. The screen name is a fixed
application label such as `catalog`, not the title or a model identifier. A
screen value may create multiple controllers; each controller gets a separate
`screenID`, and each accepted request gets a separate `updateID`.

The controller owns its sink while it is alive. Sinks must not retain a
controller, mutate observed state or UI, perform network I/O, or flush exporters
in the synchronous main-actor callback. Export configuration belongs to the
application. With telemetry absent, no telemetry IDs, timestamps, intervals, or
counter objects are created. Optional checks remain on the existing update path.

## Measured boundaries

| Phase | Begin | End |
| --- | --- | --- |
| `update` | Accepted explicit request, scheduled state reread, or initial state read | Final layout completes, before client completion code |
| `schedulingWait` | State update task scheduled | That task starts processing |
| `stateRead` | Observed state/title read starts | State reader returns |
| `identityValidation` | Requested identity validation starts | Validation passes or rejects the request |
| `queueWait` | Validated request enters the FIFO queue | Request becomes active |
| `snapshotPrepare` | Maps, renderer lookup, and snapshot preparation start | Snapshot is ready for native apply |
| `snapshotApply` | Native diffable apply called | Native apply completion starts |
| `supplementary` | Managed visible supplementary update starts | Managed update calls finish |
| `layout` | Final layout invalidation begins | `layoutIfNeeded()` returns |

The initial interval begins after collection and data-source construction. It
is not an application launch or first-screen-presentation metric. An explicit
request may include loading an unloaded controller as part of its total time.
Animated `snapshotApply` includes native animation duration; it is wall time,
not CPU time. Nested phase durations must not be added to their enclosing update.

`update` measures **update settled**, not a displayed frame. Layout completion
does not prove GPU completion or display presentation. Cell-provider counts
cover calls during an active update, not later scrolling. SwiftUI body/layout
work and content-configuration callbacks running outside that interval are not
automatically captured. Patchwork shares the controller lifecycle because it
supplies ScreenKit renderers; adapter-specific attribution is a later extension.

## Clock and work semantics

`ScreenTelemetryTimestamp` captures wall time for correlation and monotonic
uptime nanoseconds for elapsed time. Delivery or export time must never replace
source time. A reversed monotonic pair is invalid, not a zero-duration sample.
The OTel prototype anchors trace end time to wall start plus monotonic duration
so wall-clock corrections cannot create negative spans.

The terminal update includes requested section/item counts, renderer-factory
calls, cell-provider calls, managed supplementary updates, and counts of IDs
passed to reload/reconfigure. Reconfigure count does not mean that every item
was rendered. Counts are not measurements of allocations, view body evaluation,
or state property writes.

Observation is one-shot and coalesced. One reread/application yields one measured
update, even when a benchmark performs many mutations. The harness must record
its own number of mutations. No telemetry callback changes Observation scheduling.

Each begun interval gets one terminal boundary. Outcomes are `completed`,
`cancelled` (controller release), `rejected` (identity), or `stateUnavailable`
(weak state read failed). Active and pending intervals close on controller release.
Release timestamps are captured immediately; cancellation delivery is deferred
to the main actor without retaining the controller or state. Completed sessions
leave the lifetime registry immediately, so it does not grow across updates.
Ignored structural calls on reactive screens are not accepted updates and emit
no update interval. Invalid identity closes intervals before its precondition.

## Signposts and raw reports

`ScreenSignpostTelemetry` uses subsystem `com.soundblaster.ScreenKit`, category
`UIPerformance`, and fixed names such as `screenkit.update`,
`screenkit.snapshot.prepare`, `screenkit.snapshot.apply`, and `screenkit.layout`.
Every interval has a unique signpost ID, including concurrent controllers.
Signposts are emitted synchronously at sink delivery; their timing can differ
slightly from captured source time by callback/instrumentation cost.

`ScreenTelemetryRecorder` retains at most its configured event capacity. Its
`droppedEventCount` must be included in a report; overflow makes the raw report
incomplete. Raw events are Codable and preserve interval/update/controller IDs.

## OpenTelemetry mapping

The independent prototype is in
`ScreenKit-Examples/Packages/ScreenKitOpenTelemetry`. Its library depends only
on `OpenTelemetryApi`; its tests configure `OpenTelemetrySdk` 2.5.1. That API's
instrument builders do not expose units, so applications pass SDK-created
instruments with explicit seconds and count units.

Root spans are `screenkit.update`, kind INTERNAL, with explicit no-parent
context. Phase spans have their update root as parent. Causal interaction or
network contexts can be added as links, including additional coalesced causes.
The adapter does not infer dataflow from an ambient active span.

| Instrument | Type | Unit |
| --- | --- | --- |
| `screenkit.update.settled.duration` | Histogram | `s` |
| `screenkit.update.phase.duration` | Histogram, `screenkit.phase` dimension | `s` |
| `screenkit.update.count` | Counter, terminal outcome dimension | `{update}` |
| `screenkit.work.count` | Counter, `screenkit.work` dimension | `{operation}` |

Durations and work are recorded for completed updates only; phase observations
are held until the whole update completes. Noncompleted updates remain visible
through spans and the outcome counter. Trace sampling never controls metric
recording. Percentiles come from histogram aggregation, not exported client
percentiles. SDK bucket advice can be overridden by application views.

Metric dimensions: fixed `app.screen.name`, bounded `screenkit.update.kind`,
`screenkit.update.animated`, terminal outcome, schema version, and phase/work
kind when applicable. Instance/update IDs occur only on spans. Models' stable
IDs, dynamic titles, row contents, and exact item counts are not metric labels.
`app.screen.name` follows a Development OTel semantic convention; custom keys
use the `screenkit` namespace and explicit schema version `1`.

## Verification and remaining measurements

The prototype verifies balanced intervals, coalescing, independent controllers,
identity rejection, release cancellation, source-clock behavior, OTel span
parentage, explicit links, units, metric dimensions, and sampling independence.
The consumer test additionally changes a real visible cell and fans events out
to signposts, a raw recorder, and the OTel adapter.

The overhead smoke scenario changes one visible row with stable identity in a
1,000-item list. It compares disabled, signposts, OTel with an in-memory exporter,
and combined instrumentation, after equal warmups, with 20 raw repetitions per
mode. It reports configuration, OS, animations, median, and relative timing in
an xcresult JSON attachment. The fixed mode order and simulator noise mean it is
not a performance gate or a device-performance claim. A Release device run with
alternating mode order is required before setting budgets.

Next: run on a physical device, measure real batch/OTLP exporter overhead and
offline buffering, introduce equivalent UIKit/ScreenKit/Patchwork/SwiftUI
scenarios, and add frame/hitch metrics. A live collector, display presentation,
CPU attribution, and adapter-specific content categories are not verified by
this prototype. They must not be inferred from passing contract tests.
