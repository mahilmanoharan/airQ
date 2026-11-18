import SwiftUI
import RespiratoryKit

/// Everyday work is Today → History → Report. Optional tools live under More.
enum AppTab: String, Hashable, CaseIterable {
    case air, trends, report, more
}

extension EnvironmentValues {
    @Entry var selectedTab: AppTab = .air
    @Entry var openTab: @MainActor (AppTab) -> Void = { _ in }
    @Entry var openRoute: @MainActor (AppRoute) -> Void = { _ in }
    @Entry var historyPeriod: HistoryPeriod = .month
    @Entry var setHistoryPeriod: @MainActor (HistoryPeriod) -> Void = { _ in }
    @Entry var recordRevision = RecordRevision()
}

/// View refresh inputs, never persisted clinical data.
struct RecordRevision: Hashable {
    var provider = 0
    var checkIn: Date?
    var activation = 0
}

struct HistoryLoadKey: Hashable {
    let period: HistoryPeriod
    let revision: RecordRevision
    let isActive: Bool
    let retry: Int
}

extension AppRoute {
    var tab: AppTab {
        switch self {
        case .checkIn: .air
        case .trends: .trends
        case .report, .export: .report
        case .listen, .contextEvents, .records, .about, .alerts, .erase: .more
        }
    }
}

/// Existing links keep their raw route names, while their tab placement can evolve.
struct TabDestination: Equatable {
    var tab: AppTab
    var path: [AppRoute] = []

    init(_ routes: [AppRoute]) {
        guard let route = routes.first else { tab = .air; return }
        tab = route.tab
        path = route == .trends || route == .report ? Array(routes.dropFirst()) : routes
    }
}
