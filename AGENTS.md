# Project: airQ

An iOS app showing AQI and pollen for the user's location, with a home-screen widget, plus an in-progress respiratory symptom-tracking feature (cough detection → daily correlation with air quality → doctor report).

## Quick Reference
- **Platform**: iOS 26.4 (actual `IPHONEOS_DEPLOYMENT_TARGET`)
- **Language**: Swift 6 in both app/widget targets and both local packages (`swift-tools-version: 6.2`, platforms `.iOS(.v26)`/`.macOS(.v26)`). App target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; widget has no default actor override. Both Xcode targets enable approachable concurrency. Packages keep explicit isolation: main-actor presentation models, Sendable clients/DTOs, and background actors.
- **UI / Architecture**: SwiftUI, MVVM with `@Observable`

## Tooling
- **apple-docs-mcp** — current Apple API/framework docs and WWDC sessions. Use instead of relying on memory (see "Known API traps" — this project repeatedly hits APIs deprecated more recently than training data assumes).
- **XcodeBuildMCP** — build/test/simulator/log operations. UI automation (`tap`) is not enabled in this workflow config; interactive flows need manual verification.
- **swift-ios-skills** — bundled Agent Skills for SwiftUI/Swift/framework patterns.
- **Superpowers** (global skills) — reach for on substantial planning, implementation, debugging, TDD, or verification of non-trivial changes. Skip for trivial edits — just make the change and verify it directly.
- **CodeRabbit** (global reviewer) — run after substantial changes or before a PR/merge, not after every small edit. It's an independent reviewer, not a workflow gate: address valid findings normally, pulling in a Superpowers skill if the fix warrants it.

## Project Map
Folder layout and the rule for each folder are in `docs/architecture.md` ("Code map"): views only in `airQ/Views/<Feature>/`, platform adapters in `airQ/Services/`, view models/models/stores in the packages' `ViewModels/`, `Models/`, `Stores/`. Paths below name types; find their files with that map.
- `airQ/` — SwiftUI views and platform location adapter, composed by `AppServices` (opens the shared record container once, for the UI and for `BackgroundRefresh`) and shown by `AppRootView` (`airQApp.swift`). Navigation is a `TabView` (`AppTab`: Today, History, Report, More); check-in opens in Today, optional listening in More, and raw export in Report. History/Report share `HistoryPeriod` (7/30/90 days), passed as an environment value plus setter (a nested environment Binding alone does not invalidate consumers); `RecordRevision` invalidates displayed/shareable results on provider writes, check-in saves and foreground activation. `AppRoute` keeps existing raw route IDs, and every link (deep link, Siri, control, alert tap) lands via `TabDestination`. `StoreGate(\.keyPath)` shows the shared storage-failure state. No forced pop-ups or questionnaires: the welcome is the Today tab's content until "Get started"; the check-in is one question per card (`CheckInFlow`, RespiratoryKit) and nudges are passive (Today card, the week's dots); answers advance only with Next/Skip. DEBUG-only launch args (`-initialRoute`, `-autoStartListening`, `-autoExport`, `-dashboardScrollTo` (`recentAirQuality|monthSummary|dataSources`), `-explainPollutant`, `-explainScale`, `-showWelcome`, `-runBackgroundRefresh`, `-runLogNoSymptoms`, `-openCheckInFlow`, `-autoErase`, `-trendsScrollTo`, `-uiTestMode`, `-uiTestLocationDenied`, `-uiTestNoReading`, `-uiTestHistory`, `-uiTestHistoryPeriod`) exist for simulator verification without tap automation. `AQService.swift` is now a small **gitignored** `makeAirQualityClient()` credential factory; `Secrets.xcconfig` supplies `GOOGLE_POLLEN_API_KEY`. Neither exists in a fresh clone; see `docs/architecture.md` for setup. Never print these files' credential values.
- `airQWidget/` — widget extension: four independent widget kinds (`AQIWidget`, `PollenWidget`, `CombinedWidget`, `OutlookWidget`) instead of one `AppIntent`-configurable kind — WidgetKit can't scope `supportedFamilies` per config value within a single kind. Deliberate, not the default choice. AQI/Pollen also support Lock Screen accessory families, Combined the rectangular one (`AQAccessoryViews.swift`). AQI and Pollen share one entry view (`MetricWidgets.swift`, driven by `WidgetMetric`); `AQSnapshotEntry` is the timeline entry directly. The extension also ships four controls (`ScreenControls.swift`: air quality, check-in, listen, life events) whose `OpenScreenControlIntent` lives in `Shared/`, a synchronized folder compiled into **both** app and widget targets (the system requires an app-opening control intent in both; the app routes it through `NavigationRouter` via `ControlNavigation.open`, set in `airQApp.init`).
- `AirQualityKit/` (SPM) — tested `DashboardViewModel`, injected location/network/cache protocols, `HTTPAirQualityClient` (transport; parsing and wire DTOs in `ProviderResponseParsing.swift`), models, `WidgetDataStore` / `AppGroupSnapshotCache` (App Group `group.com.mahilmanoharan.airQ`), `TimelineScheduler`, `CachedPlaceLocation` (background refresh reuses the cached place; no location request). Everything the dashboard shows beyond AQI/pollen (`StationConditions`, `StationInfo`, `AirQualityForecastDay`, `DataAttribution`, pollen `plants`/`outlook`) is parsed from the same WAQI/Pollen responses and carried on `AQSnapshot` as optional fields (legacy snapshots must keep decoding). No feature may add provider requests without a budget estimate (see the Google budget rule). `AirQualitySummary` backs the Siri intent (`airQ/Services/AirQualityIntents.swift`), which reads the cache only.
- `RespiratoryKit/` (SPM) — versioned SwiftData schema (`Schema/`: V1 frozen legacy `DetectionEvent`, V2 and V3 frozen — V3 only adds `DailyCheckIn.controllerAdherence` and reuses V2's other models; any change is SchemaV4 + a migration stage) in one container shared by `DetectionStore` (capture ingest, candidates, annotations, sessions), `RecordStore` (days, provider attempts, check-ins, context events, chart series) and `RecordExporter` (CSV; per-table writers in `RecordExporter+Detections/Environment/Entries.swift`, shared helpers in `+Tables.swift`). Tested presentation models for Listen/Review/Tuning/Records/Check-in/Context/Chart; `AudioAnalysisController` + queue-confined `AnalysisPipeline` (capture semantics 2: every window with per-label scores); pure `DetectionAnalysis`, `ChartSeries`, `CheckInAnalysis`, `ContextEventResolution`. 8 respiratory-relevant SoundAnalysis labels exist on `SNClassifierIdentifier.version1` (see `RespiratoryLabels.allowlist`); **`wheeze` and `throat_clearing` do not exist as labels** on this classifier — would need a custom-trained Core ML model.

## Architecture Rules
- **RespiratoryKit governing principle**: store raw observations, derive interpretations at read time. Never persist a value with a threshold/clustering rule already applied — every `DetectionEvent` also records the config that produced it (window duration, overlap factor, classifier identifier, app version), so retuning a parameter later doesn't create an invisible discontinuity in historical data. A "bout" is an interpretation, computed live over `Sendable` DTOs — never its own stored model.
- Build **4** is SchemaV3 + check-in question set 2 (build 3 can't open a V3 store). Build **3** is capture semantics 2 (every window stored with allowlist + confounder scores, top-3, rms/peak, in a `ListeningSession` with an end reason). Build **2** removed the old 0.05 capture confidence floor. Keep app/widget build numbers in sync and advance the recorded app version when capture semantics change. Older observations remain untouched; observations discarded by older builds cannot be recovered.
- History/report inputs preserve hourly request-area provenance, pollen forecast calendar dates and original life-event dates. `AirCoverage` excludes overlapping hours across different or uncertain areas at read time; never combine them into a personal exposure peak. No schema/raw-row changes are needed for these DTOs.
- Dashboard loads coalesce; a new owner retries after a cancelled load unwinds. Cache reuse requires a fresh timestamp and coordinates within 1 km. `pollenIndex == nil` means unavailable, never measured zero. Legacy snapshots remain widget-readable but need coordinates before app cache reuse.
- Listening is owned by SwiftUI `.task(id:)`, ends on navigation, on leaving the More tab (`selectedTab`) or the Listen screen and on backgrounding, and always awaits controller cleanup; the store-owned ingest task drains every analysed window even when the view is cancelled. The live list is capped at 200; Review shows the newest 500 candidates in the chosen range with explicit access to all matches. Queries are date-ranged (a listening hour is thousands of windows).
- Annotations, check-ins and context events are append-only; the latest row wins at read time. Never mutate or delete an observation — the one exception is the person's own confirmed "Erase all data" (`EraseDataView` → `RespiratoryStore.eraseAll`), which nothing else may call. Limits never truncate stored history. Tuning interpretations are recomputed once per input change, never saved.
- `DetectionStore.open()` constructs its ModelActor off the main actor. Storage failure disables respiratory screens with an error, not the dashboard; never delete a store to make launch succeed. (After a user-confirmed erase, the next launch removes the emptied store's files — `RespiratoryStore.purgeStoreFilesIfErasePending` — only if nothing user-authored was recorded since.)

## Known API traps (verify against apple-docs-mcp before assuming any of these are still current)
Audio capture, SoundAnalysis and SwiftData traps live in `RespiratoryKit/AGENTS.md` (loaded when working in that package).
- `CLGeocoder`/`reverseGeocodeLocation` — deprecated iOS 26.0. Use `MKReverseGeocodingRequest`.
- `MKMapItem.placemark` is also deprecated iOS 26.0. For display strings use `addressRepresentations.cityName` / `regionName`.
- `INFOPLIST_KEY_<Key>` build-setting synthesis only works for Apple-recognized Info.plist keys. A custom key (e.g. the Google Pollen API key) silently never makes it into the built `Info.plist` regardless of what `-showBuildSettings` reports — verify against the actual built plist. Fix: a real merged plist via `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE = YES` (see `airQ/InfoPlistAdditions.plist`).
- xcconfig `$(NAME)` substitutes the *value* of a build setting literally named `NAME` — don't paste a secret's literal value inside the parens.

## Coding Standards
- `@Observable` for view models — never `ObservableObject` in new code
- `NavigationStack` (never `NavigationView`); `@Bindable` for bindings into `@Observable` objects; `@Environment` for DI (see `airQApp.swift`'s `detectionStore` key for threading a `@ModelActor` through the view hierarchy)
- Extract views once they exceed ~100 lines; shared semantic surfaces and adaptive accent foreground live in `AirQStyle`
- Errors: `LocalizedError` enums per domain — see `AirQualityServiceError`, `AudioAnalysisError`, and `LocationError`

## Testing
- Unit tests required for all ViewModels; UI tests for critical flows only. Use Swift Testing (`@Test`, `#expect`) — the convention throughout both packages.
- UI tests: `airQUITests` (XCUITest, critical flows only) via `xcodebuild test -project airQ.xcodeproj -scheme airQUITests -destination 'id=<sim>'`. They launch with DEBUG `-uiTestMode YES` (an in-memory record store and a credential-less client, so no real history is written and no provider request is sent). Keep it that way.

## DO NOT
- Introduce `ObservableObject` view models, or use UIKit where SwiftUI covers the need
- Force-unwrap (`!`) without an inline comment justifying why it's safe
- Ignore Swift 6 concurrency warnings — treat as build blockers (real warnings have surfaced real races here, see `AudioAnalysisController.swift`)
- In `RespiratoryKit`: persist a thresholded/derived value (an `isAboveThreshold` bool, a `Bout` model, a precomputed count) — always compute at read time from raw stored events (see Architecture Rules)

## Build & Test Commands
- **Everything**: `scripts/verify.sh [--ui]` — both package suites + a fresh-DerivedData app build (+ UI tests), each from a temporary scratch path. Prints only warnings, errors and pass/fail lines.
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
