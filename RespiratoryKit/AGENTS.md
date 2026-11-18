# RespiratoryKit

Package-scoped guidance; the root `AGENTS.md` still applies.

## Known API traps (verify against apple-docs-mcp before assuming any of these are still current)
- `AVAudioSession.requestRecordPermission(_:)` — deprecated iOS 17.0. Use `AVAudioApplication.requestRecordPermission()`.
- `AVAudioNode.installTap` — deprecated iOS 27.0, but its replacement (`installAudioTap`) is iOS 27.0+ and still Beta, unusable on this iOS 26 target. `installTap` is still correct here; its closure just isn't `@Sendable`.
- `SNResultsObserving` requires `NSObjectProtocol` — the observing type can never be a Swift `actor`; keep it a trivial plain class that only forwards results.
- `AVAudioNodeTapBlock` is not `@Sendable`. Non-Sendable types captured inside it (`SNAudioStreamAnalyzer`, `AVAudioPCMBuffer`) need an explicit, justified `@unchecked Sendable` wrapper, not `@preconcurrency` suppression.
- Copy PCM samples before handing them to the analysis queue; do not assume the engine's tap buffer has transferred ownership. All analyzer mutation after setup, including teardown, stays on that queue. Backlog overflow must stop with an explicit error, not silently discard observations.
- `@Model` classes are `Sendable` by macro expansion, but a live instance is still tied to the `@ModelActor` that fetched it. Cross actor boundaries with plain `Sendable` DTOs instead (see `DetectionSnapshot`).
- `PersistentIdentifier` has no public initializer — don't use it as an id type in anything you want to unit-test with fixture data; use a plain `UUID` field instead.
