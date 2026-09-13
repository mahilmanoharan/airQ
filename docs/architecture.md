# airQ architecture

## Boundaries and ownership

The app remains SwiftUI + Observation with two local Swift packages, no remote dependencies, and iOS 26.4 support. All targets now use Swift 6 language mode. This is a focused modernization, not a switch to a third-party architecture framework.

- **App:** `AppRootView` constructs the dashboard's dependencies after SwiftUI establishes view identity. Views retain their presentation models with `@State`; tuning bindings use `@Bindable`. `@Entry` environment values carry the shared detection store and startup error. `LocationManager` is the main-actor Core Location/MapKit adapter.
- **AirQualityKit:** `DashboardViewModel` owns one coalesced load; Sendable `HTTPAirQualityClient` handles provider requests and decoding outside the app's default main-actor isolation. Protocols separate location, networking, and caching for tests.
- **RespiratoryKit:** main-actor feature models depend on `AudioAnalyzing` / `DetectionStoring`. `AudioAnalysisController` owns session lifecycle; `AnalysisPipeline` confines analyzer work and teardown to one serial queue. `DetectionStore` owns SwiftData access; only value snapshots cross its actor boundary.
- **Widgets:** the same three existing widget kinds read the shared snapshot. They do not acquire location or make network requests. Hourly timeline refresh rereads cached data; only opening/refreshing the app fetches new readings.

## Data and concurrency behavior

Dashboard cache reuse requires a timestamp less than an hour old (not future-dated) and a coordinate within 1 km of the current fix. Independent AQI, pollen, and city-name requests run concurrently. Pull-to-refresh bypasses freshness. Concurrent loads share completion; if the previous view's operation was cancelled, a returning view starts a new operation after cleanup. A same-location stale reading stays visible on refresh failure. Cache failure does not erase an already displayed matching reading.

Pollen transport/decoding/missing-data failure produces an unavailable value (`nil`), not zero. App and widgets display a dash and “Unavailable”; the combined widget still shows valid AQI. Legacy JSON without coordinates still decodes. The App Group and `AQSnapshot.latest` key are unchanged.

Listening uses a view-owned `.task(id:)`, reserves its session before requesting permission, and awaits teardown before returning to idle. PCM samples are deep-copied before queue transfer. Analyzer errors, interruptions, input configuration changes, storage failures, and overload are visible. Audio work has an eight-buffer queue bound and a 512-result stream bound; overload ends the session with an error instead of hiding data loss. Only the latest 200 classifications are retained for live display.

Stored observations remain the top-ranked classifier result for respiratory-allowlisted labels, with no confidence threshold. No audio files or derived bouts/counts are persisted. Build **2** marks removal of the previous 0.05 capture cutoff using the existing recorded app-version field; historical rows and their metadata are not rewritten. This does not recover classifications discarded by build 1, nor turn top-ranked classifications into medically validated symptom counts.

Review initially queries the newest 500 rows in the database's requested order, updates a single annotation without reloading history, and offers “Load all history.” Tuning computes its filter/debounce/cluster pipeline once per raw-data or parameter change, preserving existing interpretation rules. Tuning and explicit full-history review still load all requested history; profile large real histories before introducing pagination or background summary computation.

SwiftData initialization happens in the package's non-main-actor async factory. A storage initialization error leaves air-quality functionality usable and offers a restart-to-retry message for respiratory screens. No schema change, store deletion, or destructive migration is part of this refactor.

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

On September 12, 2026: clean Swift Testing runs passed **27 AirQualityKit tests** and **24 RespiratoryKit tests**, with no compiler warnings. Fresh DerivedData Debug and Release simulator builds passed; the Debug app installed/launched on iPhone 17 Pro / iOS 26.4 and displayed newly updated San Francisco AQI/pollen readings. No app-level UI-test target exists. CodeRabbit CLI was unavailable; local review and targeted regressions were performed instead.

Before a release, manually verify:

1. Location denial/restriction, permission grant, offline retry, pull-to-refresh, rapid dashboard/listen navigation, and large Dynamic Type.
2. Physical-device microphone permission, rapid start/stop, interruption/route changes, foreground-to-background stop, continued raw-event storage, and review annotations after relaunch.
3. All supported widget sizes, unavailable pollen with valid AQI, and App Group updates after refresh.
4. Large-history tuning responsiveness and sustained audio CPU/memory use. Reduced duplicate work and bounded queues are structural improvements, not a measured performance/battery benchmark.

Apple references used for this refactor are recorded in [the implementation plan](superpowers/plans/2026-09-12-modernization.md).
