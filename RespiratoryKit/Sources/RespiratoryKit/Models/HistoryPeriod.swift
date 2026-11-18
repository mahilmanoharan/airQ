import Foundation

/// The same calendar-day period for the history workspace and the report it produces.
public enum HistoryPeriod: Int, CaseIterable, Identifiable, Sendable {
    case week = 7, month = 30, quarter = 90
    public var id: Int { rawValue }
    public var title: String { "\(rawValue) days" }
    public var exportPeriod: ExportPeriod {
        switch self {
        case .week: .last7
        case .month: .last30
        case .quarter: .last90
        }
    }
}
