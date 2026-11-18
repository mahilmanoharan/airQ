import Foundation
import SwiftData

/// One stored provider attempt without its raw body: enough to explain what happened.
public struct AttemptSummary: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let provider: String
    public let requestKind: String
    /// The stored raw value; unknown future statuses are kept verbatim rather than guessed.
    public let status: String
    public let httpStatus: Int?
    public let requestedAt: Date
    public let failureDetail: String?
    public let pageIndex: Int?
    /// Hourly rows this attempt returned (history requests only).
    public let hourCount: Int

    public init(id: UUID, provider: String, requestKind: String, status: String, httpStatus: Int?,
                requestedAt: Date, failureDetail: String?, pageIndex: Int?, hourCount: Int) {
        self.id = id
        self.provider = provider
        self.requestKind = requestKind
        self.status = status
        self.httpStatus = httpStatus
        self.requestedAt = requestedAt
        self.failureDetail = failureDetail
        self.pageIndex = pageIndex
        self.hourCount = hourCount
    }
}

/// How much hourly history is stored for a provider. Overlapping requests keep every row, so
/// `rowCount` can exceed `distinctHours`; de-duplication is a read-time concern.
public struct HourlyCoverage: Sendable, Equatable {
    public let rowCount: Int
    public let distinctHours: Int
    public let earliest: Date?
    public let latest: Date?

    public init(rowCount: Int, distinctHours: Int, earliest: Date?, latest: Date?) {
        self.rowCount = rowCount
        self.distinctHours = distinctHours
        self.earliest = earliest
        self.latest = latest
    }

    public static let empty = HourlyCoverage(rowCount: 0, distinctHours: 0, earliest: nil, latest: nil)
}

/// Row counts per stored table, so a phone check can confirm every part of the record is filling.
public struct RecordCounts: Sendable, Equatable {
    public var listeningSessions = 0
    public var classifierWindows = 0
    public var legacyDetections = 0
    public var annotations = 0
    public var checkIns = 0
    public var contextEvents = 0
    public var providerAttempts = 0
    public var hourlyRows = 0

    public init() {}
}

extension RecordStore {
    public func recordCounts() throws -> RecordCounts {
        var counts = RecordCounts()
        counts.listeningSessions = try modelContext.fetchCount(FetchDescriptor<ListeningSession>())
        counts.classifierWindows = try modelContext.fetchCount(FetchDescriptor<ClassifierWindow>())
        counts.legacyDetections = try modelContext.fetchCount(FetchDescriptor<DetectionEvent>())
        counts.annotations = try modelContext.fetchCount(FetchDescriptor<DetectionAnnotation>())
        counts.checkIns = try modelContext.fetchCount(FetchDescriptor<DailyCheckIn>())
        counts.contextEvents = try modelContext.fetchCount(FetchDescriptor<ContextEvent>())
        counts.providerAttempts = try modelContext.fetchCount(FetchDescriptor<EnvironmentalObservation>())
        counts.hourlyRows = try modelContext.fetchCount(FetchDescriptor<HourlyAirQuality>())
        return counts
    }

    public func recentAttempts(limit: Int) throws -> [AttemptSummary] {
        var descriptor = FetchDescriptor<EnvironmentalObservation>(
            sortBy: [SortDescriptor(\.requestedAt, order: .reverse)])
        descriptor.fetchLimit = max(1, limit)
        let rows = try modelContext.fetch(descriptor)
        let ids = rows.map(\.id)
        var hourRows = FetchDescriptor<HourlyAirQuality>(predicate: #Predicate { ids.contains($0.observationID) })
        hourRows.propertiesToFetch = [\.observationID]  // Counting only; skip the index/pollutant blobs.
        let hours = try modelContext.fetch(hourRows)
        let hourCounts = Dictionary(grouping: hours, by: \.observationID).mapValues(\.count)
        return rows.map {
            AttemptSummary(id: $0.id, provider: $0.provider, requestKind: $0.requestKind, status: $0.status,
                           httpStatus: $0.httpStatus, requestedAt: $0.requestedAt,
                           failureDetail: $0.failureDetail, pageIndex: $0.pageIndex,
                           hourCount: hourCounts[$0.id] ?? 0)
        }
    }

    public func hourlyCoverage(provider: String) throws -> HourlyCoverage {
        var descriptor = FetchDescriptor<HourlyAirQuality>(
            predicate: #Predicate { $0.provider == provider }, sortBy: [SortDescriptor(\.hourStart)])
        descriptor.propertiesToFetch = [\.hourStart]  // Only times are needed, not the index blobs.
        let starts = try modelContext.fetch(descriptor).map(\.hourStart)
        guard let first = starts.first, let last = starts.last else { return .empty }
        return HourlyCoverage(rowCount: starts.count, distinctHours: Set(starts).count, earliest: first, latest: last)
    }
}
