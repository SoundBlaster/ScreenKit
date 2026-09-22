# ScreenKit roadmap

This document is the canonical plan for `ScreenState`, stable identity, and
automatic observation in ScreenKit. It records the contract that the package
offers to feature code, the compatibility rules for existing UIKit models, and
the evidence required before a version release.

## Current direction

ScreenKit is the UIKit screen boundary. A feature owns its state and models;
ScreenKit owns the collection view, diffable data source, snapshot lifecycle,
renderer lookup, and visible supplementary updates. Patchwork remains the
adapter layer for legacy cells, UIKit views, content configurations, and
SwiftUI content.

Reactive behavior is based on Swift Observation and is available from the
minimum supported deployment target, iOS 18. iOS 27 may provide additional
UIKit behavior, but it is not a prerequisite for reactive screens.

## Identity contract

### Reactive screens

`stableID` is the only identity source for a state-backed screen. Section and
item identity must remain stable for the lifetime of the represented entity and
must be unique within the screen:

```swift
@MainActor
@Observable
final class ProductsState: ScreenState {
    var sections: [ProductsSection] = []
}

struct ProductsSection: ScreenSectionModel {
    typealias ID = UUID
    let stableID: ID
    var items: [Product]
}

struct Product: StableIdentifiable {
    typealias ID = UUID
    let stableID: ID
    var name: String
}
```

The state-backed `Screen` initializer installs an internal identity provider.
The provider must be used consistently for:

- diffable snapshots and public `sectionIDs`/`itemIDs`;
- `itemsByID` and `renderersByID`;
- renderer replacement checks;
- `reloadItems` and `reconfigureItems`;
- duplicate section and item diagnostics.

The identity provider must not fall back to a model's unrelated legacy `id`.
For a type whose `ID` cannot be inferred from `stableID`, declare it explicitly
(`typealias ID = UUID`, for example).

### Legacy and explicit screens

The existing `Screen(items, renderer:)` and `ScreenSection` APIs retain their
current behavior. They use their explicit section and item IDs and do not
require `ScreenState`, `@Observable`, or `StableIdentifiable`.

Existing models can adopt the reactive identity contract in an integration
module without changing their stored representation:

```swift
extension LegacyProduct: StableIdentifiable {
    var stableID: UUID { legacyID }
}
```

Duplicate IDs fail with a diagnostic precondition before a snapshot is applied.
Item IDs are globally unique across sections because that is a requirement of
the diffable data source.

## Observation and update lifecycle

The state reader is installed when a controller is created and is tracked with
`withObservationTracking`. A state mutation schedules one coalesced update on
the main actor. The update path reads the current state, validates identity,
updates item and renderer maps, applies the snapshot, refreshes the title and
visible supplementary content, and invalidates layout when needed.

The same scheduling path covers reads made by:

- the state and title providers;
- the section layout provider;
- the cell renderer factory;
- the cell renderer's configuration;
- supplementary view creation;
- supplementary view updates before and after a view becomes visible.

Snapshot application is serialized through the update queue. Reentrant state
changes and completion handlers are queued behind the active update, so an
observation is not registered repeatedly and snapshot application cannot create
a recursive update loop. The relay keeps a weak controller reference, and its
internal state-reader reference does not retain the state. Client-supplied
title, layout, renderer, and supplementary closures may capture state strongly;
the no-retention guarantee does not override those captures. Clients that need
state to be released before the controller should use weak captures in those
closures as well.

## Public API review

This section records the review decisions and separates the intended contract
from behavior that still needs implementation. Names are retained for now:
`ScreenState` describes the feature-owned source, `ScreenSectionModel` separates
that source model from the explicit `ScreenSection` value, and
`StableIdentifiable` describes the identity capability. The review found no
clear naming improvement that justifies a source-breaking rename.

### State ownership and update authority

- The feature or its coordinator owns and retains a state value for as long as
  the screen is in use. Passing state to `Screen` does not transfer ownership
  to the controller.
- The feature must retain state while it expects the screen to update. If state
  is released before the first read, the screen starts empty. If it is released
  after a snapshot is applied, the controller keeps that snapshot and receives
  no further updates. This preserves the last visible content without making
  the controller an owner of feature state.
- For a reactive screen, state is the sole authority for sections and items.
  Calls to the public `setSections` and `setItems` methods are ignored and logged;
  their completion closures are not called. Mutate state to change structure.
  Keep `refreshContent`, `refreshSupplementaryContent`, and `invalidateLayout`
  available for explicit refreshes of non-observed inputs.
- State observations schedule work asynchronously on the main actor and the
  resulting snapshot animates. ID accessors report the controller's applied
  snapshot, which may briefly lag behind state. Mutations observed before a
  scheduled update may be applied together; this is not a transaction over user
  code. Keep this animation policy for now; a configurable policy can be
  considered separately if a concrete use case appears.

### Identity and diagnostics

- Reactive screens use `stableID` for section and item identity in every
  snapshot, lookup map, renderer comparison, reload, reconfigure, and public ID
  accessor. They never fall back to a different legacy `id` value.
- Because `StableIdentifiable` refines `Identifiable`, `stableID` and `id` have
  the same associated type. A legacy model with (for example) `id: Int` cannot
  adopt a `stableID: UUID` without changing or adapting its `Identifiable.ID`
  type. Keep this constraint for now and document it explicitly.
- Section IDs must be unique among sections. Item IDs must be unique across all
  sections because the diffable data source has one item identity space. If the
  same domain entity appears as two independent rows, those presentations need
  distinct stable IDs; moving one row between sections should preserve its ID.
- Duplicate IDs are programmer errors and currently trigger preconditions
  before snapshot application. Improve the diagnostics to identify the
  conflicting positions and section context. Add negative tests so the
  precondition behavior is verified, not merely present in source.
- Runtime checks can detect duplicates in one snapshot, but cannot prove that
  an ID remains stable across time. State this as a caller requirement.

New conformers should have a compile-checked example that declares the
`Identifiable.ID` type explicitly and implements only `stableID`; legacy
conformances should separately demonstrate the supported same-ID-type adapter.

## Delivered implementation

The initial implementation and its verification were delivered in:

- `030ec7e` — observable `ScreenState` support;
- `3005def` — state identity, renderer tracking, coalescing, lifecycle, and
  verification-gap tests;
- `b9c179e` — reactive supplementary-content coverage;
- `ae4032f` — supplementary updates asserted on the original view;
- PR #5 and PR #6 — merged to `main`.

The external consumer proof lives in `ScreenKit-Examples` (`ScreenKitLab` and
`ToNaTo`). Its CI has two complementary jobs:

- runtime tests on Xcode 27 and an iOS 27 simulator;
- unsigned compile-only builds with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.

## Verification matrix

This matrix distinguishes source implementation from direct behavioral
evidence. A feature is only marked verified when a test exercises that path.
The entries below are an audit of the checked-in tests and examples at this
revision; they are not a report that the release gates were rerun.

### Reactive behavior directly covered in ScreenKit tests

- [x] Use `stableID` rather than a different legacy `id` value for state-backed
      section and item snapshots.
- [x] Recompute renderer selection after an observed state property changes.
- [x] Update a rendered cell after a state property read by its renderer changes.
- [x] Observe shared state independently from two controllers.
- [x] Coalesce the tested burst of state mutations into one renderer-factory
      update.
- [x] Release state when the controller is released and client closures do not
      retain it.

### Reactive behavior still needing direct tests

- [x] Add a reactive section and an item through state mutations.
- [x] Remove and reorder reactive sections.
- [x] Remove, reorder, and move reactive items between sections.
- [x] Change an item's own content while preserving its `stableID` and verify
      the visible cell payload updates.
- [x] Verify state reads in the layout provider on the iOS 18 fallback path.
- [x] Verify observation during supplementary-view creation and repeated
      updates to the same visible supplementary view through a reactive
      controller.
- [x] Verify duplicate section IDs and globally duplicate item IDs are
      diagnosed through `ScreenViewController` before snapshot enqueue, with
      conflict positions in the message and the applied snapshot unchanged.
- [x] Verify that explicit structural updates are ignored on a reactive
      controller and that later state mutations remain authoritative.
- [x] Verify that the controller does not retain state and preserves its last
      applied snapshot after state is released.
- [x] Verify that a screen starts empty when state is released before its first
      read.

The ScreenKitLab header UI test uses the explicit `Screen(sections, renderer:)`
initializer and calls `refreshSupplementaryContent`; it verifies explicit
refresh after scrolling, not automatic observation through `ScreenState`.

### Explicit API and compile-level evidence

- [x] Explicit APIs expose caller-provided section and item IDs.
- [x] The package regression test verifies a state-backed model whose legacy
      `id` value differs from `stableID`.
- [x] Compile a new `StableIdentifiable` model that defines only `stableID`
      plus an explicit `typealias ID`.
- [x] Compile a legacy adapter with the same `Identifiable.ID` type and verify
      that reactive snapshots still use `stableID` when its value differs from
      the model's existing `id`.
- [x] Add negative macro tests for malformed `#screen` argument shapes and
      assert the diagnostic text and source location.
- [x] Add duplicate-ID diagnostic tests and assert useful conflict context.
- [x] Document which controller update methods are valid on reactive screens.
- [x] Document state lifetime and snapshot-vs-state timing in README and DocC.
- [x] Document identity namespaces and the same-type `Identifiable.ID`
      constraint in README and DocC.
- [x] Explain that iOS 27 is not required for reactive behavior.
- [x] Keep README and DocC state examples executable: they start with a section
      or show the section being added.

### Previously completed release evidence

Earlier iOS 18 simulator, DocC, symbol-scan, and consumer-CI results are recorded
in their original PRs. This change reruns the package tests and iOS 18 simulator
suite; a release still requires fresh evidence for every gate listed below.

### Fresh package verification

- iOS 18.6 simulator: 28 tests passed, 0 failures, 0 skips. Result bundle:
  `/tmp/ScreenKit-NegativeMacros-Final-20260923.xcresult`.
- `swift test`: 10 macro tests passed, 0 failures.
- DocC generated for the iOS 18 target with the GitHub Actions command and the
  iOS 27 SDK; no warnings. Output:
  `/tmp/ScreenKit-Identity-DocC-Verified-20260923`.
- `git diff --check` passed.

### Release gates

Before changing the package version or preparing a release PR, run all of the
following and retain the result paths in the PR description:

- `swift test`;
- iOS 18 simulator build and test, including an `.xcresult` bundle;
- DocC using the iOS SDK and the same command used by GitHub Actions;
- a symbol/documentation scan with no new unresolved-symbol warnings;
- the `ScreenKit-Examples` consumer build and runtime checks.

The release must preserve the iOS 18 deployment target and must not introduce a
requirement for iOS 27-only APIs in the reactive path.

## Next planned work

The next changes should be delivered in small, reviewable steps:

1. Add focused tests for duplicate IDs, the `stableID`-only conformance,
   reactive removals/reorders/moves, iOS 18 layout observation, and reactive
   supplementary observation. Keep the existing explicit-refresh UI test
   labeled as such.
2. Document identity namespaces and the same-type `Identifiable.ID` constraint
   in README and DocC, then reconcile every verification row against an
   executable test.
3. Re-run the release-gate matrix and attach fresh evidence before publishing
   the next package version.
