import SwiftUI

/// Routes to tab roots and screens within each tab.
enum AppRoute: String, Hashable, CaseIterable {
    case checkIn, trends, report, listen, contextEvents, records, export, about, alerts, erase

    var title: String {
        switch self {
        case .checkIn: "Check-in"
        case .trends: "History"
        case .report: "Report"
        case .listen: "Listen"
        case .contextEvents: "Life events"
        case .records: "Stored data"
        case .export: "Export raw records"
        case .about: "About & data"
        case .alerts: "Air quality alerts"
        case .erase: "Erase all data"
        }
    }

    static let moreMenu: (actions: [AppRoute], privacy: [AppRoute]) = {
        let actions: [AppRoute] = [.contextEvents, .alerts]
        let privacy: [AppRoute] = [.records, .about, .erase]
        assert(Set(actions + privacy) == Set(allCases.filter { $0.tab == .more }),
               "Every More route must appear in the menu")
        return (actions, privacy)
    }()

    var systemImage: String {
        switch self {
        case .checkIn: "checklist"
        case .trends: "chart.xyaxis.line"
        case .report: "doc.text"
        case .listen: "waveform"
        case .contextEvents: "calendar.badge.plus"
        case .records: "tray.full"
        case .export: "square.and.arrow.up"
        case .about: "info.circle"
        case .alerts: "bell"
        case .erase: "trash"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .checkIn: StoreGate(\.checkInModel) { CheckInView(model: $0) }
        case .trends: TrendsDestinationView()
        case .report: StoreGate(\.recordStore) { _ in ReportView() }
        case .listen: StoreGate(\.detectionStore) { ListenView(store: $0) }
        case .contextEvents: StoreGate(\.recordStore) { ContextEventsView(store: $0) }
        case .records: StoreGate(\.recordStore) { RecordsView(store: $0) }
        case .export: StoreGate(\.respiratoryContainer) { ExportView(container: $0) }
        case .about: AboutView()
        case .alerts: AlertsView()
        case .erase: StoreGate(\.respiratoryContainer) { EraseDataView(container: $0) }
        }
    }

    nonisolated static let urlScheme = "airq"

    /// `airq://<route>` (e.g. `airq://checkIn`). Used by Siri/Shortcuts and any other deep link.
    nonisolated var url: URL {
        URL(string: "\(Self.urlScheme)://\(rawValue)") ?? URL(filePath: "/")  // Literal ASCII; always valid.
    }

    /// The path a deep link opens: a route, or the dashboard (`airq://dashboard`, empty path).
    /// Nil for anything else, which is ignored.
    nonisolated static func path(for url: URL) -> [AppRoute]? {
        guard url.scheme?.lowercased() == urlScheme, let host = url.host() else { return nil }
        if host.lowercased() == "dashboard" { return [] }
        return AppRoute(rawValue: host).map { [$0] }
            ?? allCases.first { $0.rawValue.lowercased() == host.lowercased() }.map { [$0] }
    }

    /// Debug builds accept `-initialRoute <route>` so a screen can be opened directly on the
    /// simulator for verification without UI automation.
    static var initialPath: [AppRoute] {
        #if DEBUG
        UserDefaults.standard.string(forKey: "initialRoute").flatMap(AppRoute.init(rawValue:)).map { [$0] } ?? []
        #else
        []
        #endif
    }
}
