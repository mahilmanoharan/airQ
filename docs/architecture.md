# airQ architecture

## Code map (MVVM, one rule per folder)

Views live only in the app; view models, models and services live in the packages, so anything with logic is unit-tested with `swift test`.

```
airQ/                       app target (SwiftUI). Config files (plists, entitlements, xcconfig, AQService.swift) stay at this level.
  App/                      entry point, composition (AppServices), navigation (AppTab tabs, AppRoute screens), UI-test fixtures
  Views/{Dashboard,CheckIn,Listen,Trends,Data,Settings}/   screens by feature (Today, Listen, History, Report, More); a view owns @State view models and no business logic
  Services/                 platform adapters: location, background refresh, provider-attempt recording, alerts, Siri intents, data eraser, tuning preference
airQWidget/                 widget extension: four widget kinds + four controls, read the shared snapshot only
Shared/                     compiled into both app and widget: the control intent (system requires both)
AirQualityKit/Sources/AirQualityKit/
  Models/                   AQSnapshot, forecast, pollen, station, provider-attempt value types
  ViewModels/               DashboardViewModel (+ LoadGate)
  Services/                 HTTP client + parsing, request budget, history collector, cache, contracts (protocols)
  Presentation/             wording, colours and spoken summaries for AQI / pollen
  Policies/                 pure rules: alert decisions, widget timeline scheduling
RespiratoryKit/Sources/RespiratoryKit/
  Schema/                   versioned SwiftData models (V1–V3 frozen)
  Models/                   value types: check-ins, context events, capture, tuning, LocalDay, ClinicianSummary
  Stores/                   actors over SwiftData: DetectionStore, RecordStore, RequestLedger; protocols for injection
  Capture/                  microphone + SoundAnalysis pipeline
  Analysis/                 read-time interpretation: debounce/threshold, chart series
  Export/                   CSV writers and the archive exporter
  ViewModels/               one @Observable model per screen (Listen, Review, Tuning, Records, Check-in, Trends, Export, ...)
```

Tests sit in each package's `Tests/` and are named for what they cover. New screen: a view in `airQ/Views/<Feature>/`, its model in a package's `ViewModels/`, its data types in `Models/`.

## Boundaries and ownership

The app remains SwiftUI + Observation with two local Swift packages, no remote dependencies, and iOS 26.4 support. All targets now use Swift 6 language mode. This is a focused modernization, not a switch to a third-party architecture framework.

- **App:** `AppServices` composes the long-lived services once (the shared record container, the dashboard and a background model) after SwiftUI establishes view identity; `AppRootView` renders them. Views retain their presentation models with `@State`; tuning bindings use `@Bindable`. `@Entry` environment values carry the shared detection store and startup error. `LocationManager` is the main-actor Core Location/MapKit adapter.
- **AirQualityKit:** `DashboardViewModel` owns one coalesced load; Sendable `HTTPAirQualityClient` handles provider requests and decoding outside the app's default main-actor isolation. Protocols separate location, networking, and caching for tests.
- **RespiratoryKit:** main-actor feature models depend on `AudioAnalyzing` / `DetectionStoring`. `AudioAnalysisController` owns session lifecycle; `AnalysisPipeline` confines analyzer work and teardown to one serial queue. `DetectionStore` owns SwiftData access; only value snapshots cross its actor boundary.
- **Widgets:** the four widget kinds (AQI, Pollen, Combined, Outlook) read the shared snapshot. They do not acquire location or make network requests. Hourly timeline refresh rereads cached data. New readings come from opening the app or from background app refresh (below).

## Everyday navigation and reports

Today puts the place and reading time above two interactive AQI and pollen cards. The cards show their meaning inline, sit in a horizontal scroll view at standard text sizes, and stack at accessibility sizes. Tapping a card zooms from that card into its details and scale. Tomorrow’s forecast precedes the check-in, which remains available when air data fails and opens the first question when the loaded day has no saved check-in. Check-in uses explicit Next/Skip. The Listen tab sits beside Today. Listen deep links open its root screen. Capture starts through **Start listening**, and past sessions have their own link. Listening stops when leaving the Listen tab or screen, or when the app moves to the background. Erasing the record clears the listening stack and any results held by its view model. History shows the latest check-in and opens date inspection, side-by-side charts, and listening history in dedicated views. A calendar and day arrows share the chart selection with the date inspector. Report shows the date range, a plain-language summary, and preview and sharing actions. The preview contains clinical measures, coverage, weekly figures, and the plain-text summary. The one-page US Letter PDF is generated in memory, and raw export remains available under Advanced. Existing deep-link route names still resolve through `TabDestination`.

`HistoryPeriod` defines shared 7/30/90-day calendar ranges. Its environment value and setter are separate so changes invalidate both views. `RecordRevision` includes provider writes, check-in saves and foreground activation; together with period and active tab it forms each view’s load key. Older results and share actions are hidden as soon as the key changes. Raw export is an advanced Report destination; runs own separate temporary directories, obsolete completions cannot replace newer results, and launch cleanup removes abandoned `airQ-export-*` copies. Siri’s no-symptoms write requires local device authentication.

## Data and concurrency behavior

Dashboard cache reuse requires a timestamp less than an hour old (not future-dated) and a coordinate within 1 km of the current fix. The city-name lookup runs alongside the AQI request; pollen is requested only after AQI succeeds (metered, so a failed AQI request never costs a pollen request). Pull-to-refresh bypasses freshness, except that a reading fetched under a minute ago is reused. Concurrent loads share completion; if the previous view's operation was cancelled, a returning view starts a new operation after cleanup. A same-location stale reading stays visible on refresh failure. Cache failure does not erase an already displayed matching reading.

Pollen transport/decoding/missing-data failure produces an unavailable value (`nil`), not zero. App and widgets display a dash and “Unavailable”; the combined widget still shows valid AQI. Legacy JSON without coordinates still decodes. The App Group and `AQSnapshot.latest` key are unchanged.

Listening uses a view-owned `.task(id:)` and reserves its session before requesting permission. PCM samples are deep-copied into eight preallocated slots (one per queue permit) before queue transfer, and frames are counted from the session's first buffer. Every analysis window is persisted (capture semantics 2, build 3): a score for each allowlisted and confounder label at any rank, the top three labels, and input RMS/peak. Persistence runs in a task owned by `DetectionStore` and batched every 50 windows or 5 s. Cancelling the view stops capture, but the pipeline flushes its final window (`completeAnalysis()`, confirmed by `requestDidComplete`) and the store drains every buffered window before the session is closed with an end reason. The display stream keeps only the newest windows; the persistence stream ends with an error rather than drop one.

Review verdicts, check-ins and context events are append-only; the latest row wins at read time, and a legacy `isFalsePositive` flag is only the baseline. Review, tuning, sessions and trends query a chosen date range. Tuning computes filter → debounce → bouts once per input change; debounce chains from the previous raw detection so grouping doesn't depend on confidence order.

Every environmental request attempt (including failures, skipped budget and unavailable location) is stored with its raw body. A day with no `DailyRecord` is "not collected"; a recorded day whose attempts all failed is "collected, no data". Trends derive everything at read time, off the main actor, including the by-hour-of-day view (events plus listening time per local hour, so counts always carry their exposure). Export writes one CSV per table plus a generated data dictionary, raw bodies and a checksummed manifest, verifying row counts so an export is complete or fails. An export can be limited to a recent period (rows selected by when they were recorded, stated in the manifest, README and notes), which is a shareable partial copy rather than a backup.

History preserves request-area coordinates on hourly DTOs. Hours with overlapping readings from different areas (the existing 10 km area rule), or known and unknown areas together, are omitted from combined charts and daily summaries; `AirCoverage` reports omissions and legacy unknown areas. Store/export rows remain unchanged. Pollen is grouped by the provider’s calendar forecast date; only legacy rows without that date fall back to the local request day. Context spans retain original date keys for labels and clinician reports, while plotted start/end dates stay clipped to the selected period.

SwiftData initialization happens in the package's non-main-actor async factory. A storage initialization error leaves air-quality functionality usable (Google requests are refused because usage can't be counted) and offers a restart-to-retry message for respiratory screens. The schema is versioned (V1 legacy, V2, V3 current, all frozen; V3 only adds the check-in's controller-adherence answer); a model change requires SchemaV4 and a migration stage. The store is never deleted to make launch succeed. The only deletion is the person's own confirmed "Erase all data". AppServices cancels and awaits the foreground and background loads, history collection, listening and exports. It flushes provider writes and pauses both store writers through deletion. It clears the shared snapshot and invalidates loaded views and drafts. The next launch removes the emptied store's files unless something user-authored was recorded since.

## Background refresh and alerts

`BackgroundRefresh` schedules updates only when the user enables Background updates in the Air quality alerts screen. iOS decides when it runs, at least an hour out. Each provider request requires current location authorization. A run loads through a second `DashboardViewModel` whose location is `CachedPlaceLocation` — the last cached place and name — so it makes no CoreLocation request and no geocoding request, and the same rules apply: a fresh cache means no request, pollen is requested at most once per local day, and Google history is not collected. A user who moves keeps widgets on the old place (named on the widget) until the app is opened.

Alerts are opt-in and local. `AirQualityAlertPolicy` (pure, in AirQualityKit) decides which of the air (AQI threshold) and pollen (index threshold, today's forecast only) notifications are due, each at most once per local day; `AirQualityAlerts` posts them on the device after a background run. Those runs send the rounded saved area to air data providers.

## Local credentials

`airQ/AQService.swift` remains ignored and now only supplies credentials to the tracked HTTP client. For a fresh clone, create that file locally:

```swift
import Foundation
import AirQualityKit

func makeAirQualityClient() -> HTTPAirQualityClient {
    HTTPAirQualityClient(
        waqiToken: "YOUR_LOCAL_WAQI_TOKEN",
        pollenAPIKey: Bundle.main.object(forInfoDictionaryKey: "GooglePollenAPIKey") as? String ?? "",
        bundleIdentifier: Bundle.main.bundleIdentifier
    )
}
```

Supply `GOOGLE_POLLEN_API_KEY` through the existing ignored `Secrets.xcconfig`; `InfoPlistAdditions.plist` merges it into the built plist. Do not commit either credential file. Bundled client credentials are extractable from an installed app; this refactor does not replace them with a backend credential proxy.

## Verification and remaining checks

As of September 29, 2026 (branch `cook`): **114 RespiratoryKit tests** and **101 AirQualityKit tests** pass with no warnings, and the 12 UI tests (`airQUITests`) pass with no skips. That includes an on-disk V2→V3 migration test; the simulator store migrated to V3 with its rows intact. Debug simulator builds have 0 warnings. On an iOS 26.4 simulator, a Listen session stored contiguous windows with an end reason, an export of that store produced every table, and the background-refresh path (DEBUG `-runBackgroundRefresh YES`) refreshed the cached reading with location permission revoked.

Before a release, manually verify on a physical device:

1. Microphone permission, the first-run disclosure, rapid start/stop, interruption (a call), route change (AirPods), backgrounding, and that Sessions shows each end reason.
2. Long listening sessions: CPU, memory, battery and store growth (about 2,400 windows per hour: 3 s windows with 50% overlap).
3. The check-in flow in under 5 seconds, VoiceOver across every health screen and chart, and large Dynamic Type.
4. Export → share to Files, then open the CSVs in a spreadsheet and check the manifest checksums.
5. Location denial, offline retry, pull-to-refresh, all widget sizes, and unavailable pollen with valid AQI.
6. Background refresh and alerts: that iOS actually runs the refresh (widgets update without opening the app), the notification permission prompt, an alert arriving once per day per kind, and the hint shown when Background App Refresh is off.

Apple references used for this refactor are recorded in [the implementation plan](superpowers/plans/2026-09-12-modernization.md).
