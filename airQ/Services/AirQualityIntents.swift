import AppIntents
import AirQualityKit

/// "What's the air quality?" answered from the cached snapshot the widgets also read. It never
/// fetches, so Siri/Shortcuts can't spend provider requests.
struct CurrentAirQualityIntent: AppIntent {
    static let title: LocalizedStringResource = "Current Air Quality"
    static let description = IntentDescription("Tells you the latest AQI and pollen reading airQ has saved.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AirQualitySummary.sentence(for: WidgetDataStore.loadLatest())))
    }
}

/// The same cached reading plus the EPA's guidance for its category. Read-only, like the summary.
struct AirQualityAdviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Air Quality Guidance"
    static let description = IntentDescription("Tells you the latest AQI and the EPA guidance for that level.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AirQualitySummary.advice(for: WidgetDataStore.loadLatest())))
    }
}

struct AirQualityShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CurrentAirQualityIntent(),
                    phrases: ["What's the air quality in \(.applicationName)",
                              "Check \(.applicationName)",
                              "\(.applicationName) air quality"],
                    shortTitle: "Air Quality",
                    systemImageName: "aqi.medium")
        AppShortcut(intent: AirQualityAdviceIntent(),
                    phrases: ["\(.applicationName) air quality guidance",
                              "What's the air quality guidance in \(.applicationName)"],
                    shortTitle: "Air Quality Guidance",
                    systemImageName: "text.bubble")
        AppShortcut(intent: LogNoSymptomsIntent(),
                    phrases: ["Log no symptoms in \(.applicationName)",
                              "No symptoms today in \(.applicationName)"],
                    shortTitle: "No Symptoms Today",
                    systemImageName: "checkmark.circle")
        AppShortcut(intent: OpenScreenIntent(),
                    phrases: ["Open \(\.$screen) in \(.applicationName)",
                              "Show \(.applicationName) \(\.$screen)"],
                    shortTitle: "Open Screen",
                    systemImageName: "rectangle.stack")
    }
}

/// The screens Siri/Shortcuts can open. Navigation only: nothing is recorded or prompted.
enum AirQScreen: String, AppEnum {
    case dashboard, checkIn, trends, report, listen, contextEvents, records, export, about, alerts, erase

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "airQ Screen"
    static let caseDisplayRepresentations: [AirQScreen: DisplayRepresentation] = [
        .dashboard: "Dashboard", .checkIn: "Check-in", .trends: "History", .report: "Report", .listen: "Listen",
        .contextEvents: "Life events", .records: "Stored data", .export: "Export data", .about: "About & data", .alerts: "Air quality alerts", .erase: "Erase all data",
    ]

    /// Exhaustive over `AppRoute`, so a new route can't be added without a Siri screen for it.
    @MainActor init(_ route: AppRoute) {
        switch route {
        case .checkIn: self = .checkIn
        case .trends: self = .trends
        case .report: self = .report
        case .listen: self = .listen
        case .contextEvents: self = .contextEvents
        case .records: self = .records
        case .export: self = .export
        case .about: self = .about
        case .alerts: self = .alerts
        case .erase: self = .erase
        }
    }

    @MainActor var path: [AppRoute] {
        self == .dashboard ? [] : AppRoute.allCases.filter { AirQScreen($0) == self }
    }
}

/// Hands a navigation request from an intent to the app's root view. The intent runs in the app
/// (it opens it), so no URL round trip and no "Open in airQ?" confirmation is needed.
@MainActor @Observable
final class NavigationRouter {
    static let shared = NavigationRouter()
    var pendingPath: [AppRoute]?
}

struct OpenScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open airQ Screen"
    static let description = IntentDescription("Opens airQ on the chosen screen.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Screen", default: .checkIn)
    var screen: AirQScreen

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$screen)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationRouter.shared.pendingPath = screen.path
        return .result()
    }
}
