import SwiftUI

/// Every screen besides the dashboard: three are tabs (`tab`), the rest are listed under More.
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

    /// The More tab's grouping: noting life events, managing the record, settings/about, and erasing.
    /// The everyday screens (check-in, listen, trends) are tabs of their own.
    static let menuSections: [[AppRoute]] = {
        let sections: [[AppRoute]] = [[.listen, .contextEvents], [.alerts], [.records, .about], [.erase]]
        // A screen that is neither a tab nor in More is easy to lose (this once hid Alerts and Erase).
        let tabs = Set(allCases.filter { $0.tab != .more })
        assert(Set(sections.joined()).union(tabs) == Set(allCases) && sections.joined().allSatisfy { $0.tab == .more },
               "Every AppRoute must be a tab or appear in a More section")
        return sections
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
