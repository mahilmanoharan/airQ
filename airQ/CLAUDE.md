# Project: [Your App Name]

> ⚠️ **Before using this file**: the bracketed placeholders below (`[...]`) are things I couldn't know without seeing your actual code. Once you drop this in your project root, open Claude Code there and say:
> *"Read this CLAUDE.md and my codebase, then fill in every `[placeholder]` with the real values — project structure, dependencies, existing feature list, package manager, etc. Don't guess; look at the actual files."*
> That gets you an accurate file instead of one with silent wrong assumptions.

## Quick Reference
- **Platform**: iOS 18+
- **Language**: Swift 6+
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with `@Observable`
- **Package Manager**: [Swift Package Manager / CocoaPods / Mixed — confirm]
- **Minimum Deployment**: iOS 18.0

## Tooling (already configured for this project)
- **apple-docs-mcp**: for looking up current Apple API/framework documentation and WWDC sessions. Use this instead of relying on memory for API signatures.
- **XcodeBuildMCP**: for all build, test, simulator, and log operations. Check `/mcp` for the exact registered tool names — they're scoped to the workflows enabled in `.mcp.json` (currently: simulator, project-discovery, swift-package).
- **swift-ios-skills**: bundled Agent Skills for SwiftUI/Swift/framework patterns. These activate automatically based on context — no need to invoke them explicitly.

## Project Structure
```
[Run a directory listing and paste the real structure here — e.g.:
MyApp/
├── App/
├── Features/
│   ├── [ActualFeatureName]/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── Models/
├── Core/
├── Resources/
└── Tests/]
```

## Existing Features
[List the actual feature modules that already exist in this codebase, so Claude doesn't duplicate or misname things — e.g. Authentication, Onboarding, Settings, etc.]

## Coding Standards

### Swift Style
- Use Swift 6 strict concurrency (`Sendable`, actors, structured concurrency)
- Use `@Observable` for view models — do not introduce `ObservableObject` in new code
- Use `async/await` for all asynchronous operations
- Follow Apple's Swift API Design Guidelines
- Prefer `guard` for early exits
- Prefer value types (structs) over reference types unless identity/mutation semantics require a class

### SwiftUI Patterns
- Extract views when they exceed ~100 lines
- Use `@State` for local view state only
- Use `@Environment` for dependency injection
- Use `NavigationStack` (never the deprecated `NavigationView`)
- Use `@Bindable` for bindings into `@Observable` objects

### Navigation Pattern
```swift
// Type-safe routing with NavigationStack
enum Route: Hashable {
    case detail(Item)
    case settings
}

NavigationStack(path: $router.path) {
    ContentView()
        .navigationDestination(for: Route.self) { route in
            // handle routing
        }
}
```

### Error Handling
```swift
enum AppError: LocalizedError {
    case networkError(underlying: Error)
    case validationError(message: String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error): return error.localizedDescription
        case .validationError(let msg): return msg
        }
    }
}
```

## Testing Requirements
- Unit tests for all ViewModels
- UI tests for critical user flows only (not every screen)
- Use the Swift Testing framework (`@Test`, `#expect`) for new tests
- [Confirm actual coverage target / CI requirement, if any]

## DO NOT
- Introduce `ObservableObject` view models — this project standardizes on `@Observable`
- Use UIKit where SwiftUI already covers the need
- Create monolithic views — extract subviews once a view grows large
- Force-unwrap (`!`) without an inline comment justifying why it's safe
- Ignore Swift 6 concurrency warnings — treat them as build blockers, not noise

## Build & Test Commands
- **Build**: use XcodeBuildMCP's simulator build tool (check `/mcp` for exact name)
- **Test**: use XcodeBuildMCP's test tool for the relevant target
- **Clean**: run a clean build before investigating flaky failures
- **Logs**: use XcodeBuildMCP's log capture tool to debug runtime issues on simulator

## Working Agreement
- Read relevant existing code before adding a new feature — don't assume patterns, verify them against real files in this repo
- For anything touching architecture or a non-trivial refactor, propose a plan before editing
- Keep this file updated as the project's real structure and conventions evolve — a stale CLAUDE.md is worse than none
