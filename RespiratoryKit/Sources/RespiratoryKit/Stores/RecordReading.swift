import Foundation

public protocol RecordReading: Sendable {
    func dailyRecords() async throws -> [DailyRecordSnapshot]
    func providerRequestCount(provider: String, since date: Date) async throws -> Int
    func recentAttempts(limit: Int) async throws -> [AttemptSummary]
    func hourlyCoverage(provider: String) async throws -> HourlyCoverage
    func recordCounts() async throws -> RecordCounts
}

extension RecordStore: RecordReading {}
