# Project: airQ

An iOS app showing AQI and pollen for the user's location, with a home-screen widget, plus an in-progress respiratory symptom-tracking feature (cough detection → daily correlation with air quality → doctor report).

## Quick Reference
- **Platform**: iOS 26.4 (actual `IPHONEOS_DEPLOYMENT_TARGET`)
- **Language**: Swift 6.0 in both app/widget targets and both local packages (`swift-tools-version: 6.0`). App target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; widget has no default actor override. Both Xcode targets enable approachable concurrency. Packages keep explicit isolation: main-actor presentation models, Sendable clients/DTOs, and background actors.
- **UI / Architecture**: SwiftUI, MVVM with `@Observable`
- **Packages**: SPM, two local packages (`AirQualityKit`, `RespiratoryKit`), no remote dependencies

## Tooling
- **apple-docs-mcp** — current Apple API/framework docs and WWDC sessions. Use instead of relying on memory (see "Known API traps" — this project repeatedly hits APIs deprecated more recently than training data assumes).
- **XcodeBuildMCP** — build/test/simulator/log operations. UI automation (`tap`) is not enabled in this workflow config; interactive flows need manual verification.
- **swift-ios-skills** — bundled Agent Skills for SwiftUI/Swift/framework patterns.
- **Superpowers** (global skills) — reach for on substantial planning, implementation, debugging, TDD, or verification of non-trivial changes. Skip for trivial edits — just make the change and verify it directly.
- **CodeRabbit** (global reviewer) — run after substantial changes or before a PR/merge, not after every small edit. It's an independent reviewer, not a workflow gate: address valid findings normally, pulling in a Superpowers skill if the fix warrants it.

## Project Map
- `airQ/` — SwiftUI views and platform location adapter, composed in `AppRootView` (`airQApp.swift`). `AQService.swift` is now a small **gitignored** `makeAirQualityClient()` credential factory; `Secrets.xcconfig` supplies `GOOGLE_POLLEN_API_KEY`. Neither exists in a fresh clone; see `docs/architecture.md` for setup. Never print these files' credential values.
- `airQWidget/` — widget extension: three independent widget kinds (`AQIWidget`, `PollenWidget`, `CombinedWidget`) instead of one `AppIntent`-configurable kind — WidgetKit can't scope `supportedFamilies` per config value within a single kind. Deliberate, not the default choice.
- `AirQualityKit/` (SPM) — tested `DashboardViewModel`, injected location/network/cache protocols, `HTTPAirQualityClient`, models, `WidgetDataStore` / `AppGroupSnapshotCache` (App Group `group.com.mahilmanoharan.airQ`), `TimelineScheduler`.
- `RespiratoryKit/` (SPM) — three tested presentation models, audio/storage protocols, `SoundClassifierProbe`, `AudioAnalysisController`, queue-confined `AnalysisPipeline`, `DetectionEvent` (`@Model`), `DetectionStore` (`@ModelActor`), `DetectionAnalysis`. 8 respiratory-relevant SoundAnalysis labels exist on `SNClassifierIdentifier.version1` (see `RespiratoryLabels.allowlist`); **`wheeze` and `throat_clearing` do not exist as labels** on this classifier — would need a custom-trained Core ML model.

## Architecture Rules
- **RespiratoryKit governing principle**: store raw observations, derive interpretations at read time. Never persist a value with a threshold/clustering rule already applied — every `DetectionEvent` also records the config that produced it (window duration, overlap factor, classifier identifier, app version), so retuning a parameter later doesn't create an invisible discontinuity in historical data. A "bout" is an interpretation, computed live over `Sendable` DTOs — never its own stored model.
- Build **2** removes the old 0.05 capture confidence floor. Keep app/widget build numbers in sync and advance the recorded app version when capture semantics change. Older observations remain untouched; observations discarded by older builds cannot be recovered.
- Dashboard loads coalesce; a new owner retries after a cancelled load unwinds. Cache reuse requires a fresh timestamp and coordinates within 1 km. `pollenIndex == nil` means unavailable, never measured zero. Legacy snapshots remain widget-readable but need coordinates before app cache reuse.
- Listening is owned by SwiftUI `.task(id:)`, ends on navigation/backgrounding, and always awaits controller cleanup. The live list is capped at 200; initial review fetch is newest 500 with explicit access to all history. Limits never truncate stored history. Tuning interpretations are recomputed once per input change, never saved.
- `DetectionStore.open()` constructs its ModelActor off the main actor. Storage failure disables respiratory screens with an error, not the dashboard; never delete a store to make launch succeed.

## Known API traps (verify against apple-docs-mcp before assuming any of these are still current)
- `CLGeocoder`/`reverseGeocodeLocation` — deprecated iOS 26.0. Use `MKReverseGeocodingRequest`.
- `MKMapItem.placemark` is also deprecated iOS 26.0. For display strings use `addressRepresentations.cityName` / `regionName`.
- `AVAudioSession.requestRecordPermission(_:)` — deprecated iOS 17.0. Use `AVAudioApplication.requestRecordPermission()`.
- `AVAudioNode.installTap` — deprecated iOS 27.0, but its replacement (`installAudioTap`) is iOS 27.0+ and still Beta, unusable on this iOS 26 target. `installTap` is still correct here; its closure just isn't `@Sendable`.
- `SNResultsObserving` requires `NSObjectProtocol` — the observing type can never be a Swift `actor`; keep it a trivial plain class that only forwards results.
- `AVAudioNodeTapBlock` is not `@Sendable`. Non-Sendable types captured inside it (`SNAudioStreamAnalyzer`, `AVAudioPCMBuffer`) need an explicit, justified `@unchecked Sendable` wrapper, not `@preconcurrency` suppression.
- Copy PCM samples before handing them to the analysis queue; do not assume the engine's tap buffer has transferred ownership. All analyzer mutation after setup, including teardown, stays on that queue. Backlog overflow must stop with an explicit error, not silently discard observations.
- `@Model` classes are `Sendable` by macro expansion, but a live instance is still tied to the `@ModelActor` that fetched it. Cross actor boundaries with plain `Sendable` DTOs instead (see `DetectionSnapshot`).
- `PersistentIdentifier` has no public initializer — don't use it as an id type in anything you want to unit-test with fixture data; use a plain `UUID` field instead.
- `INFOPLIST_KEY_<Key>` build-setting synthesis only works for Apple-recognized Info.plist keys. A custom key (e.g. the Google Pollen API key) silently never makes it into the built `Info.plist` regardless of what `-showBuildSettings` reports — verify against the actual built plist. Fix: a real merged plist via `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE = YES` (see `airQ/InfoPlistAdditions.plist`).
- xcconfig `$(NAME)` substitutes the *value* of a build setting literally named `NAME` — don't paste a secret's literal value inside the parens.

## Coding Standards
- Swift 6 strict concurrency (`Sendable`, actors, structured concurrency) in all targets (see Quick Reference)
- `@Observable` for view models — never `ObservableObject` in new code
- `async/await` for all async operations; `guard` for early exits; prefer structs over classes unless identity/mutation semantics require one
- `NavigationStack` (never `NavigationView`); `@Bindable` for bindings into `@Observable` objects; `@Environment` for DI (see `airQApp.swift`'s `detectionStore` key for threading a `@ModelActor` through the view hierarchy)
- Extract views once they exceed ~100 lines
- Errors: `LocalizedError` enums per domain — see `AirQualityServiceError`, `AudioAnalysisError`, and `LocationError`; `ErrorType` remains a legacy public API

## Testing
- Unit tests required for all ViewModels; UI tests for critical flows only. Use Swift Testing (`@Test`, `#expect`) — the convention throughout both packages.
- Run: `cd AirQualityKit && swift test` / `cd RespiratoryKit && swift test`; app/widget targets via XcodeBuildMCP's test tool (no app-level test target exists yet).

## DO NOT
- Introduce `ObservableObject` view models, or use UIKit where SwiftUI covers the need
- Create monolithic views — extract subviews once a view grows large
- Force-unwrap (`!`) without an inline comment justifying why it's safe
- Ignore Swift 6 concurrency warnings — treat as build blockers (real warnings have surfaced real races here, see `AudioAnalysisController.swift`)
- In `RespiratoryKit`: persist a thresholded/derived value (an `isAboveThreshold` bool, a `Bout` model, a precomputed count) — always compute at read time from raw stored events (see Architecture Rules)

## Build & Test Commands
- **Build**: XcodeBuildMCP `build_sim`/`build_run_sim` (session defaults: project, scheme, simulator)
- **Clean**: use a fresh task-specific DerivedData path when packages/Info.plist change; plain `clean` has not always picked these up. For stale SwiftPM module-cache warnings, run `swift test --scratch-path <fresh-temporary-directory>`; don't delete unrelated build artifacts.
- **Logs**: XcodeBuildMCP log capture; for live-fetch verification, the shared App Group plist can be read directly off the simulator filesystem (`.../Containers/Shared/AppGroup/<uuid>/Library/Preferences/group.com.mahilmanoharan.airQ.plist`)

## Agent Handoff (Claude Code ↔ Codex)
This repo may be worked on by Claude Code or Codex.

**Starting work**: read `HANDOFF.md`, run `git status --short` and `git diff --stat`, inspect only the changed files relevant to the active task, and continue from the recorded next step rather than re-exploring completed work.

**While working**: inspect summaries/structure first, load detailed files/diffs/docs only when needed. Don't reread large portions of the repo when targeted inspection suffices, and don't duplicate information already available from code, Git, tests, or this file.

**Handing off**: update `HANDOFF.md` after meaningful milestones and before intentionally switching agents. Record only what the next agent would otherwise have to rediscover, and replace stale information rather than accumulating history.

## Working Agreement
- Read relevant existing code before adding a new feature — verify patterns against real files, don't assume
- For anything touching architecture or a non-trivial refactor, propose a plan before editing
- Keep this file updated as the project's real structure/conventions evolve — a stale CLAUDE.md is worse than none
