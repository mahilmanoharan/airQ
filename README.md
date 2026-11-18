# airQ

An iOS app that shows air quality (AQI) and pollen for your location, with home-screen and Lock Screen widgets, plus a respiratory history you can compare with air quality and share with a clinician. It is descriptive only: it shows readings and your own records side by side and draws no medical conclusions.

- **Air quality**: current reading, pollutant sub-indices, weather, a forecast and a 48-hour history chart (World Air Quality Index Project + Google Air Quality).
- **Pollen**: a daily forecast by type, with a multi-day outlook (Google Pollen).
- **Widgets**: AQI, Pollen, Combined and a 4-day Outlook, plus Lock Screen accessories. They read a cached snapshot; opening the app and optional Background updates keep it current.
- **Alerts** (opt-in, local): unhealthy air and high pollen.
- **Tomorrow** on the dashboard: the forecast air quality and pollen, for planning.
- **Controls** for Control Center, the Lock Screen and the Action button: the saved AQI, Daily Check-in, Listen and Life Events.
- **Siri / Shortcuts**: the saved reading, EPA guidance, "No symptoms today" (a one-step check-in that never overwrites recorded symptoms), opening any screen, and `airq://<screen>` deep links.
- **Today**: tappable AQI and pollen cards, tomorrow’s forecast, and a check-in.
- **Listen**: on-device cough analysis and past listening sessions. Audio is never stored.
- **History and Report**: day details and comparison charts, plus a printable clinician summary. Both tabs share 7/30/90-day periods. Raw CSV/provider archives are available under Report’s advanced export, for everything or the last 7/30/90 days. Records stay on the device until you choose to share.
- **More**: life events, alerts and stored-data tools.

## Layout

| Path | What it is |
| --- | --- |
| `airQ/` | SwiftUI app: views, location adapter, background refresh, alerts, intents |
| `airQWidget/` | WidgetKit extension (four widget kinds and four controls) |
| `Shared/` | Compiled into both the app and the widget: the controls' open-screen intent |
| `AirQualityKit/` | Swift package: models, provider client, dashboard model, timeline scheduling, alert policy |
| `RespiratoryKit/` | Swift package: versioned SwiftData store, capture pipeline, presentation models, export |
| `airQUITests/` | XCUITest suite for critical flows |
| `docs/architecture.md` | Boundaries, data rules and the pre-release device checklist |
| `AGENTS.md` | Conventions and traps for contributors and coding agents |

iOS 26.4, Swift 6 strict concurrency, SwiftUI with `@Observable`. No third-party dependencies.

## Setup

Provider credentials are not in the repository. Create `airQ/AQService.swift` and `airQ/Secrets.xcconfig` locally as described in [docs/architecture.md](docs/architecture.md#local-credentials); both are git-ignored. Without them the app builds but cannot fetch readings.

## Tests

`scripts/verify.sh` runs both package suites and an app build from fresh scratch paths; `scripts/verify.sh --ui` adds the UI tests (set `SIM_UDID` to choose a simulator). Individually:

```sh
cd AirQualityKit && swift test
cd RespiratoryKit && swift test
xcodebuild test -project airQ.xcodeproj -scheme airQUITests -destination 'id=<simulator-udid>'
```

The UI tests launch with a DEBUG `-uiTestMode YES` argument: an in-memory store, fixed reading and location, and no network. Other DEBUG launch arguments (`-initialRoute`, `-runBackgroundRefresh`, …) are listed in `AGENTS.md`.
