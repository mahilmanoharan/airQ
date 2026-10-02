# Cook Experience Implementation Plan

> **For agentic workers:** Use the parallel-agent skill for independent file scopes; root integrates and verifies all tasks. The user's explicit design delegation authorizes execution on cook without additional gates.

**Goal:** Make Today → History → Report the clear, reliable core experience.
**Architecture:** Preserve packages and stores; update read-time DTOs and views. SwiftUI navigation uses four tabs and retains route raw values. No new dependency or schema migration.
**Tech Stack:** Swift 6, SwiftUI, Swift Charts, SwiftData, Swift Testing, iOS 26.4.
**Spec:** `docs/superpowers/specs/2026-09-30-cook-experience-design.md`

## Global constraints
- Work only on cook; retain all preexisting uncommitted work. Local feature commits on cook are now authorized; do not push or merge with main.
- No new provider requests, accounts, raw-data deletion, persisted interpretations or schema edits.
- No secret output. Native accessible UI. Missing data stays unknown.

## Review focus
- A period change followed by an error must never leave the old summary shareable.
- Travel/history backfill and UTC pollen dates must not falsely align exposure with symptoms.
- Existing links and optional listening must still route and stop correctly.
- Empty, partial and populated records must all produce honest, useful screens.
- Large text and sharing cancellation must not hide actions or retain stale exports.

## Task 1 — Correct report/history inputs (package owner)
Files: RespiratoryKit Models/ChartModels, Analysis/ChartSeries, Models/ClinicianSummary, Stores/RecordStore+EnvironmentSeries, ViewModels/ClinicianSummaryViewModel, related tests.
- [ ] Add regression cases for forecast-date grouping, original event dates, summary reload failure and mixed-place hourly history; watch failures before fixes.
- [ ] Preserve optional DTO provenance with compatible initializers; filter/label mixed places explicitly rather than claim exposure.
- [ ] Clear prior summary at load start; test load failure after success.
- [ ] Run RespiratoryKit suite with a fresh scratch path. Report API additions to UI owners.

## Task 2 — History workspace (History UI owner)
Files: airQ/Views/Trends/*.swift only.
- [ ] Replace blank plots with an actionable empty state, introduce coverage and a shared period control (7/30/90 days).
- [ ] Put symptoms and air/pollen adjacent; move sounds/listening/medication detail into disclosures when present.
- [ ] Keep selection inspection visible and preserve accessibility labels; avoid recomputing expensive derived values on selection.
- [ ] Add History → Report and check-in actions using environment openRoute and shared selectedHistoryPeriod.
- [ ] Root verifies seeded and empty screens and critical UI routes.

## Task 3 — Report experience (Report UI owner)
Files: airQ/Views/Data/ReportView.swift (new), SummarySection.swift, ExportView.swift; no package edits.
- [ ] Create ReportView for a readable 30-day default summary with 7/30/90-day controls shared with History.
- [ ] Lead with coverage/counts and a full readable preview; share current plain text only after loading completes.
- [ ] Advanced raw export remains available by NavigationLink to existing ExportView.
- [ ] Root verifies reporting, period changes, raw export and errors.

## Task 4 — Navigation, Today and integration (root)
Files: AppTab/AppRoute/airQApp, Views/Shared/AirQStyle, Dashboard*, CheckInFlowView, MoreView, WelcomeView, AppServices, CheckInIntents, UI fixtures/tests, package period models/tests.
- [ ] Four tabs Today/History/Report/More; retain raw route IDs and route check-in into Today, listening into More, export into Report's navigation stack.
- [ ] Add Today check-in card, compact air presentation, consistent semantic surfaces, updated welcome and More grouping.
- [ ] Use explicit progression in check-in (update UI tests); reuse original save semantics.
- [ ] Authenticate Siri writes; clean abandoned exports when services first prepare.
- [ ] Add deterministic populated demo data only behind DEBUG + uiTestMode, exercising real read-time models.
- [ ] Run package suites, fresh simulator build, critical UI tests and accessibility audits; inspect screenshots and address concrete defects.
- [ ] Independent final code review; update AGENTS/architecture/HANDOFF with final behavior and remaining device checks.

## Progress
- Design and research complete; implementation starting. Prior review preserved in HANDOFF.
