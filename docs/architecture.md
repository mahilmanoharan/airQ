# airQ architecture

airQ shows air quality and pollen for a location. It also records breathing symptoms and sound analysis results. History and Report use the saved observations to show how these measurements change over time.

## Code map

airQ uses Swift 6, SwiftUI, and Observation. The app requires iOS 26.4. It uses two local Swift packages and has no remote package dependencies.

| Path | Function |
| --- | --- |
| `airQ/App/` | Starts the app, connects its services, and manages navigation. Contains the UI test fixtures. |
| `airQ/Views/` | Contains SwiftUI views by feature. |
| `airQ/Services/` | Connects the packages to iOS services, such as location, background tasks, alerts, and Siri. Also records provider attempts and coordinates data erasure. |
| `AirQualityKit/` | Gets air quality and pollen data. Controls the request budget, collects hourly air quality history, and saves the latest reading. |
| `RespiratoryKit/` | Stores environmental records, check-ins, life events, and listening sessions. Calculates values for charts, reports, and review screens. Writes exports. |
| `airQWidget/` | Contains the AQI, Pollen, Combined, and Outlook widgets. Also contains four controls that open app screens. |
| `Shared/` | Contains the control intent. The app and widget targets both compile this intent. |

For a new screen, put the view in `airQ/Views/<Feature>/`. Put its view model and data types in the applicable package's `ViewModels/` and `Models/` folders. Put unit tests in that package's `Tests/` folder.

In AirQualityKit, find request and cache code in `Services/`. Find alert and widget scheduling rules in `Policies/`. Find display text and colors in `Presentation/`.

In RespiratoryKit, find SwiftData models in `Schema/` and database access in `Stores/`. Find microphone code in `Capture/`, calculations in `Analysis/`, and file writers in `Export/`.

Start at [airQApp.swift](../airQ/App/airQApp.swift). For air readings, continue to [DashboardViewModel.swift](../AirQualityKit/Sources/AirQualityKit/ViewModels/DashboardViewModel.swift). For saved records, continue to [RecordStore.swift](../RespiratoryKit/Sources/RespiratoryKit/Stores/RecordStore.swift).

## Boundaries and ownership

- `AppServices` prepares one SwiftData container for the app and its background tasks. It also prepares the foreground and background dashboard models. `AppRootView` shows the screens.
- SwiftUI views keep their view models in `@State`. Use `@Bindable` for bindings to an `@Observable` model. The environment carries shared dependencies and startup errors.
- `LocationManager` uses Core Location and MapKit on the main actor. `HTTPAirQualityClient` sends requests and decodes responses. The dashboard uses protocols for location, requests, and cache access so tests can supply their own implementations.
- `AudioAnalysisController` owns the listening session. `AnalysisPipeline` does the analysis and cleanup on one serial queue. `DetectionStore` writes sound results to SwiftData. Only value types cross the store's actor boundary.
- Widgets get their readings from the App Group cache. The hourly widget timeline reads this cache again. The app supplies new readings in the foreground or during background refresh.

## Everyday navigation and reports

| Tab | Function |
| --- | --- |
| Today | Shows the place and reading time. The tinted cards show the air and pollen levels in words and numbers. Tap a card to see the reading first. Open its scale with the button below it. You can share the air reading from its detail screen. At larger text sizes, the cards stack. The check-in comes before tomorrow's forecast and is available if the air data is missing. |
| Listen | Keeps **Start listening**, **Stop listening**, and the active microphone indicator above the tab bar. Past sessions and tools are separate from capture controls. |
| History | Shows the latest check-in and gives the comparison charts the primary action. **View a day** shows the date and saved readings. Use **Jump to date** for the calendar or the pinned buttons to move one day at a time. The inspector and charts use the same selected date. |
| Report | Shows the selected period and a text summary. **Share report** stays above the tab bar when the PDF is ready. Tap **Preview report** to read it first. Expand **Advanced export** for raw records. |
| More | Shows Life events and Air quality alerts. Expand **Data & privacy** for stored data, app information, and erasure. |

Tap the check-in card to open the first question if the app has loaded today's records and there is no saved check-in. If a check-in exists or the app cannot start a new one, the card opens the check-in overview. The flow shows one question per card. Use **Next** or **Skip** at the bottom to continue. **Save** stays in the same area while you review the answers.

Pollen details show the three pollen types and the forecast dates in separate rows. A missing value shows **Unavailable**. Expand **Plant details** to see the plant forecasts.

`TabDestination` maps routes to the correct tab and screen. Keep existing route IDs so links continue to work. A Listen link opens the root of the Listen tab. The Siri action that saves a no-symptoms check-in requires device authentication.

`SpotlightNavigation` submits four public screen descriptions to the iPhone search index. A Spotlight activity opens the matching screen through the same route. Only the known shortcut IDs can open a screen. The index contains no personal observations or report data.

In the report preview, **View print layout** uses PDFKit to show the PDF from **Share report**. The page supports pinch to zoom. The print layout closes if its PDF changes or becomes unavailable.

`HistoryPeriod` gives History and Report the same selection of 7, 30, or 90 calendar days. At larger text sizes, both screens use a menu for this selection. Pass the period and its setter separately through the environment. The period, active tab, and `RecordRevision` control when each screen loads its data. Provider writes, check-in saves, and a return to the foreground can change the revision. When the load inputs change, the screen hides the old results and share actions.

## Data and concurrency behavior

### Air quality and pollen

1. Get the current coordinates. Reuse a saved reading if its location is within 1 km and its age is less than one hour. A timestamp in the future is invalid for cache reuse.
2. If the app needs new data, look up the city name while the air quality request runs. Start a pollen request only after the air quality request succeeds.
3. Save the new `AQSnapshot` to the App Group cache under `AQSnapshot.latest`. The app can show the new reading if the cache write fails.

An explicit refresh can reuse a reading less than 60 seconds old after a successful load. Concurrent callers wait for the same load. If the owner cancels that load, an eligible caller can start a new load after cleanup. The foreground and background models also share a gate. After a model gets through the gate, it checks the cache again.

If a refresh fails, the app can keep a stale reading for the same location. If the location lookup fails, it can show the last saved reading. Legacy snapshots without coordinates still decode. The dashboard needs coordinates before it can use a snapshot as a cache hit.

For the same area, reuse a settled pollen response for the current local day. The app can retry after a temporary failure, such as a network error or HTTP 429. The request budget still applies. `pollenIndex == nil` means pollen data is unavailable. Zero is a valid index. The combined widget can show valid AQI when pollen is unavailable.

### Listening

The Listen view owns capture through `.task(id:)`. The controller reserves the session before it requests microphone permission. The pipeline copies pulse-code modulation (PCM) samples into eight preallocated slots before it transfers them to the analysis queue. It counts frames from the first buffer of the session.

Capture semantics version 2, introduced in build 3, stores these values for each analysis window.

- Scores for selected labels, including labels that can be confused with respiratory sounds
- The three highest-scoring labels and their scores
- The root-mean-square (RMS) and peak input levels

`DetectionStore` saves the results in a separate task. During ingest, it saves at 50 pending windows or when it processes an event at least 5 seconds after the last save. The display stream keeps the newest results. If the storage stream cannot accept a window, it reports an error.

Leaving the Listen tab or screen, or putting the app in the background, stops capture. The pipeline calls `completeAnalysis()` and waits for `requestDidComplete` with a time limit. The store saves the windows that the pipeline delivers before it records the session end reason.

### Records, charts, and exports

Store raw observations. Calculate interpretations when you read the observations. For example, tuning applies a score limit and groups nearby detections. A change to the score limit can change the groups while the saved scores stay the same. The debounce rule uses the previous raw detection to decide when a new group starts.

Every review verdict, check-in, and life-event edit adds a row. Use the latest applicable row when you read the data. A legacy `isFalsePositive` value supplies the initial review state. Review, tuning, session, and chart queries use the selected date range.

The app records provider attempts, including failures and requests it did not send. An attempt can include the original response body. A day without a `DailyRecord` is **not collected**. A recorded day can have no readings. For the chart by hour of day, calculate both detections and listening time for each local hour.

History keeps the request area with each hourly air quality reading. `AirCoverage` excludes hours with overlapping readings from different areas. The area rule uses a distance of 10 km. `AirCoverage` also excludes overlaps that mix known and unknown areas. It reports omitted hours and legacy readings with unknown areas.

Use the provider's forecast date for pollen. Use the local request date only for legacy rows that have no forecast date. Keep the original life-event dates for labels and reports. Clip the plotted span to the selected period.

Raw export writes a CSV file for each table. It also writes a data dictionary, original provider responses, and a manifest with checksums. The exporter checks row counts before it returns a result. For a limited export, select rows by when the app recorded them. The manifest and export notes give the limits. Each run uses its own temporary directory. Only the current run can publish a result. At launch, the app removes abandoned `airQ-export-*` directories.

### Storage and erasure

Open SwiftData off the main actor. If storage initialization fails, show the storage error on respiratory screens and offer a restart. Air quality can still work. The app blocks Google requests if it cannot count them.

Keep schema versions V1, V2, and V3 fixed. V1 is the legacy detection schema. V3 adds the controller-adherence answer to the V2 check-in. For a model change, add V4 and a migration stage.

Erase observations only after the user confirms **Erase all data**. A startup failure must leave the store in place. During erasure, `AppServices` stops and waits for dashboard loads, background refresh, history collection, listening, and exports. It finishes pending provider writes and pauses the store writers during deletion. The app clears the shared reading, open results, and drafts. On the next launch, it removes the emptied store files if no newer user-authored data exists.

## Background refresh and alerts

To allow background refresh, turn on **Background updates** in **More → Air quality alerts**. `BackgroundRefresh` gives iOS an earliest start time of 65 minutes after scheduling. iOS decides when to run the task.

Air quality alerts shows the setup status above the switches. Expand **How alerts work** for quiet hours, the daily limit, and delivery timing.

A background run requires current location permission and a saved place. It uses `CachedPlaceLocation` to get the saved coordinates and name. It sends the rounded coordinates if it needs a new reading. It does not request a new location fix, look up a new place name, or collect Google hourly history. If you move, open the app to get widget readings for your new place.

`AirQualityAlertPolicy` checks the AQI threshold and the pollen threshold. For pollen, it uses today's forecast. If alerts are enabled, `AirQualityAlerts` can post one local notification per kind per local day. Quiet hours are 22:00 to 07:00 local time.

## Local credentials

1. Create `airQ/AQService.swift` with the code below. Replace `YOUR_LOCAL_WAQI_TOKEN` with your WAQI token.

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

2. Create `airQ/Secrets.xcconfig`. Set `GOOGLE_POLLEN_API_KEY` to your Google Pollen API key. `InfoPlistAdditions.plist` supplies this value to the built app as `GooglePollenAPIKey`.

Keep both files local. The Git ignore rules exclude them. A person with access to the installed app can extract the bundled keys.

## Verification and remaining checks

Run `scripts/verify.sh` to test both packages and build the app. Add `--ui` to run the UI tests. The UI tests use an in-memory store and send no provider requests. See [HANDOFF.md](../HANDOFF.md) for the dated test results and open device checks.

Before release, do these checks on a physical device.

1. Check the microphone disclosure and permission prompt. Start and stop capture quickly. Repeat with a call, an audio route change, and a switch to the background. Check the end reasons in Sessions.
2. Run a long listening session. Measure CPU use, memory use, battery use, and store growth. A 3-second window with 50% overlap gives about 2,400 windows per hour.
3. Do a quick check-in. Check VoiceOver on the health screens and charts. Check the layout at large text sizes.
4. Share an export to Files. Open the CSV files in a spreadsheet and check the manifest checksums.
5. Deny location permission, then test offline retry and pull-to-refresh. Check all widget sizes. Check the display when AQI is available and pollen is unavailable.
6. Confirm that iOS can refresh the widgets without opening the app. Check the notification permission prompt, the daily limit for each alert kind, and the hint when Background App Refresh is off.

See the [modernization plan](superpowers/plans/2026-09-12-modernization.md) for the Apple references.
