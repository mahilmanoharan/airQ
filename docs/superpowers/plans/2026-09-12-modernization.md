# airQ modernization implementation plan

**Goal:** Modernize the existing app and widgets for Swift 6 while fixing redundant work, lifecycle races, and misleading missing-data states.

**Architecture:** Keep SwiftUI and the two existing packages. Main-actor `@Observable` feature models own presentation state; injected protocols isolate network, location, audio, and persistence side effects. Immutable `Sendable` values cross isolation boundaries. UI views own models with `@State` and receive shared services through the environment.

## Constraints

- iOS deployment target stays 26.4. No remote package dependencies or new product features.
- Preserve uncommitted respiratory implementation and existing SwiftData records. No destructive store reset or change to bout/threshold interpretations.
- All app/widget build configurations use Swift 6. Keep main-actor default for the app; packages retain explicit isolation.
- Keep all three widget kinds and the App Group identifier/cache key compatible.
- Raw respiratory observations remain raw; remove the undocumented confidence floor before persistence. Bound only the transient on-screen list, not stored observations.
- Work directly with the existing dirty checkout so the user can review the combined result; no commits or destructive Git operations.

## 1. Dashboard data flow

- [x] Establish package and simulator build baselines.
- [x] Add tests for freshness boundaries, coordinate-aware cache reuse, unavailable pollen, cancellation, duplicate loads, and retry.
- [x] Move dashboard feature state into AirQualityKit. Inject `AirQualityFetching`, `LocationProviding`, and `SnapshotCaching`.
- [x] Use one async load operation, concurrent independent requests, cancellation checks before publication, and stale data retained on refresh failure.
- [x] Move HTTP decoding/request construction to a tested package client. Keep local credentials outside tracked sources.
- [x] Replace view-owned location callbacks with `.task`/`.refreshable`; split dashboard content and error presentation.
- [x] Render unavailable pollen explicitly in app and widgets. Decode old snapshots without coordinates safely.

## 2. Respiratory lifecycle and presentation

- [x] Add protocol-backed tests for all three respiratory view models, including permission-pending duplicate starts, stop during start, stream failures, and failed writes.
- [x] Move models into RespiratoryKit, inject required stores/controllers, and surface errors in the views.
- [x] Finish audio setup before publication and serialize analysis/teardown on the analysis queue; give stop/termination session ownership so an old stream cannot stop a new one.
- [x] Use throwing streams, copy audio buffers before queue transfer, and finish streams on analyzer errors. Keep the supported iOS 26 audio tap API.
- [x] Bound live display history, fetch review rows in display order, and compute tuning summaries once per input/parameter change.

## 3. Integration and verification

- [x] Migrate app/widget targets to Swift 6, resolve compiler diagnostics, use current MapKit address representations, and keep one-shot location acquisition with cancellation.
- [x] Keep app launch usable when respiratory storage initialization fails; surface a recoverable error without replacing the store.
- [x] Run both Swift Testing suites and simulator Debug/Release builds; launch for smoke verification.
- [x] Check CodeRabbit availability and review changes: CLI unavailable; local review added and resolved targeted regressions.
- [x] Update AGENTS.md and HANDOFF.md; retain CLAUDE.md's existing @AGENTS.md delegation with architecture, validation, and remaining manual-device checks.

## Documentation basis

- [Swift concurrency architecture](https://developer.apple.com/videos/play/wwdc2025/268/): main actor for UI, explicit concurrency when needed.
- [SwiftUI concurrency](https://developer.apple.com/videos/play/wwdc2025/266/): separate async work from view rendering and test it independently.
- [State ownership](https://developer.apple.com/documentation/swiftui/state): avoid side effects in view state initialization.
- [One-shot location](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()): automatically stops after a fix; explicit cancellation is supported.
- [MapKit address representations](https://developer.apple.com/documentation/mapkit/mkmapitem/addressrepresentations): iOS 26 replacement for placemark display strings.
- [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor): isolated model access with value snapshots.

## Acceptance

Tests exercise production orchestration with deterministic injected boundaries (no live API keys or microphone prompts). Builds must have no Swift concurrency warnings. Manual permission dialogs, actual microphone analysis, interruptions/routes, and widget gallery appearances require simulator/device interaction beyond a compile check; report any unverified flows explicitly.
