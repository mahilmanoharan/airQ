# airQ: a personal breathing history

## Intent and authorization
The user wants an exceptionally clear, lightweight experience for seeing personal symptom history beside air quality and sharing it with clinicians. On 2026-09-30 they delegated design and implementation decisions, with all work on `cook`. Preserve the prior review in HANDOFF.md. The user subsequently authorized local feature commits on `cook` only. No push, merge with main, deployment, account changes, schema edits, or real-history deletion.

## Direction
Four destinations: Today, History, Report, More. Today has a compact current-air overview and a prominent check-in card. History is the main comparison workspace: shared 7/30/90-day selection, explicit coverage, symptoms adjacent to environmental plots, details disclosed only when useful. Report puts a readable period-specific summary first and raw export behind an explicit advanced route. More groups optional listening/life events, preferences and data management. All existing deep links remain valid.

Use system type with rounded headlines, generous spacing, warm grouped backgrounds, teal accents, white/dark semantic cards and restrained color. Avoid extra illustrations, new dependencies, scoring, causal interpretation, streaks, or unsolicited prompts. Keep 44pt controls, Dynamic Type, VoiceOver descriptions and Reduce Motion support. The check-in remains optional and never appears automatically during normal use.

## Data correctness
Carry pollen forecast dates to the chart. Retain place provenance in hourly history and avoid merging multiple places into a misleading personal exposure series. Report original life-event dates, not clipped chart dates. Invalidate summaries when a new period loads or fails. Align History and Report periods; never imply missing days are symptom-free. Retain raw observations and frozen SchemaV1/V2/V3.

## Report and privacy
Readable summary first, compact coverage and counts, full preview before sharing. Keep a plain-text sharing option and complete raw archive under Advanced export. Only offer data from the selected period. Require authentication for Siri writes. Recover abandoned temporary exports on launch. Cloud credential restrictions remain an external verification item.

## Research
- Apple Health: summary first, tap for details: https://support.apple.com/guide/iphone/view-your-health-data-iphe3d379c32/26/ios/26
- Bearable: record only relevant symptoms and share appointment reports: https://bearable.app/chronic-illness-symptom-tracker-app/
Borrow hierarchy and progressive disclosure; do not copy medical claims or add an account.

## Acceptance
All core flows remain reachable from the four tabs and existing links. Empty History explains how to begin without blank charts. Populated History visibly places symptoms beside air. Report has a clear primary share action and an accurate period. Preserve tests for capture, migrations, provider budgets and export. Add focused regression tests for correctness; update critical UI flow tests and inspect both empty and seeded populated simulator screens. Fresh app build must have zero concurrency warnings.
