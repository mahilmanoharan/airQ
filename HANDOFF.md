# Current task

User approved the Swift 6 architecture refactor after switching to Astra. Implementation and automated verification are complete; no commits were requested or made. The pre-existing respiratory feature and dirty checkout were preserved.

# What the next agent needs

- All app/widget configurations now use Swift 6; app default isolation remains MainActor. Four injected, tested `@Observable` feature models now live in the two packages. `airQ/AQViewModel.swift` was replaced by the package dashboard model.
- Ignored `airQ/AQService.swift` changed locally to `makeAirQualityClient()`, retaining local credentials; tracked HTTP logic is in AirQualityKit. A fresh clone needs that factory and `Secrets.xcconfig` recreated using `docs/architecture.md`. Never print their secrets.
- Snapshot decoding remains backward-compatible; coordinates are required for cache reuse, pollen can be unavailable. Keep all three widget kinds and existing App Group/key.
- Audio teardown is queue-confined, buffers are copied, sessions are cancellation-owned, and failures are visible. Build numbers advanced together to **2** so stored `appVersion` distinguishes removal of the old 0.05 capture cutoff. DetectionEvent schema/history and interpretation rules were not changed.
- Review initially loads newest 500 rows and exposes all history on request; live display is capped at 200. Neither limit truncates persisted observations. Full-history tuning remains an eventual scale/profiling consideration.
- `CLAUDE.md` already delegates to updated `AGENTS.md`; architecture details and manual checks are in `docs/architecture.md`. The old handoff's suggestion to revert DashboardView/airQApp is superseded by the approved refactor.

# Verification (2026-09-12)

- Clean `swift test`: **27 AirQualityKit + 24 RespiratoryKit = 51 passed**, no compiler warnings.
- Fresh DerivedData **Release build** and **Debug build/install/launch** succeeded for scheme `airQ`, including widget extension, on iPhone 17 Pro / iOS 26.4, no compiler warnings.
- Runtime screenshot showed newly updated San Francisco AQI 21 / pollen 1. A simulator-system duplicate WebKit accessibility-class diagnostic appeared; no app failure was observed.
- `git diff --check` passed. CodeRabbit CLI is not installed, so no external CodeRabbit review ran; local review added cache-failure/navigation-cancellation regressions.
- Current XcodeBuildMCP defaults: Debug, simulator `C2854D13-0C46-4EBD-90D8-87DC9C2AACED`, DerivedData `/private/tmp/airQ-final-derived.AJkFGN`. Clean package scratch directories: `/private/tmp/airQ-aq-tests.PsR80S` and `/private/tmp/airQ-respiratory-tests.6s2bUs`.

# Next

Manual checks in `docs/architecture.md` remain: permission paths, actual microphone/interruptions/backgrounding, widget gallery variants, accessibility, and performance on a physical device. No tap automation/app UI-test target is available. Then the user can review/commit the combined work if desired; do not commit automatically or discard unrelated Xcode/user files.

Respiratory chunks 3–10 (daily AQI/pollen correlation, charts, check-in, indoor/outdoor signals, background night listening, HealthKit, PDF export, correlation analysis) are still unstarted and were not added by this refactor.
