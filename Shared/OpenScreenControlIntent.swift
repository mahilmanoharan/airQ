import AppIntents

// Compiled into both the app and the widget extension: the system requires an app-opening control's
// intent to be in both, and runs `perform()` in the app.

/// Screens a Control Center, Lock Screen or Action button control can open. Raw values match `AppRoute`;
/// the dashboard is the root.
enum ControlScreen: String, AppEnum {
    case dashboard, checkIn, listen, contextEvents

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen to open"
    static let caseDisplayRepresentations: [ControlScreen: DisplayRepresentation] = [
        .dashboard: "Dashboard", .checkIn: "Check-in", .listen: "Listen", .contextEvents: "Life events",
    ]
}

/// Opens airQ on a screen. Navigation only: nothing is recorded, and Listen still waits for its Start button.
struct OpenScreenControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open airQ from a Control"
    static let supportedModes: IntentModes = .foreground
    /// Shortcuts and Siri already have "Open airQ Screen"; this one exists for controls.
    static let isDiscoverable = false

    @Parameter(title: "Screen")
    var screen: ControlScreen

    init() {}

    init(_ screen: ControlScreen) {
        self.screen = screen
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ControlNavigation.open?(screen)
        return .result()
    }
}

/// Set by the app at launch. Stays nil in the widget extension, which never performs the intent.
@MainActor
enum ControlNavigation {
    static var open: ((ControlScreen) -> Void)?
}
