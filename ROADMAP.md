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
    let stableID: UUID
    var items: [Product]
}

struct Product: StableIdentifiable {
    let stableID: UUID
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

Keep this matrix current when changing the state or observation implementation.

### Behavior

- [x] Add, remove, and reorder sections.
- [x] Add, remove, and reorder items.
- [x] Change item content while preserving `stableID`.
- [x] Support a legacy item whose legacy `id` differs from `stableID`.
- [x] React when state changes renderer selection.
- [x] React when state is read by the cell renderer.
- [x] React when state is read by the layout provider.
- [x] React when state is read by a supplementary renderer before the view
      appears and after it becomes visible.
- [x] Coalesce multiple mutations into one snapshot update.
- [x] Observe two controllers backed by the same state independently.
- [x] Release controller and state without retaining the relay.
- [x] Diagnose duplicate section and item IDs before snapshot application.

### API and documentation

- [x] Keep `stableID` as the sole identity source for reactive screens.
- [x] Keep explicit `Screen(items, renderer:)` and `ScreenSection` behavior.
- [x] Provide a compile-level example for a new `StableIdentifiable` type.
- [x] Provide a regression example for a legacy model with a different `id`.
- [x] Document state ownership, identity requirements, and update timing.
- [x] Explain that iOS 27 is not required for reactive behavior.
- [x] Keep README and DocC examples executable: state examples start with a
      section or show the section being added.

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

The next implementation changes should be treated as a separate task from this
baseline:

1. Review the public `ScreenState`, `ScreenSectionModel`, and
   `StableIdentifiable` names and diagnostics against Swift API Design
   Guidelines.
2. Expand the app-level iOS 18 UI coverage for a header that appears after
   scrolling and then changes more than once.
3. Re-run the complete release-gate matrix and attach fresh evidence before
   publishing the next package version.
