import Foundation

/// One environmental provider request attempt as captured by the app, including failures and
/// skipped requests. Parsed fields are copies of what the provider returned; `rawResponse` is truth.
public struct EnvironmentalAttemptRecord: Sendable, Equatable {
    public enum Status: String, Sendable, CaseIterable {
        case success, httpError, decodeError, missingData, networkError, missingCredentials, cancelled
        case locationUnavailable, skippedBudget
        /// Never left the device (offline, DNS or connect failure), so it isn't usage.
        case notSent

        /// Whether the attempt may have reached the provider, and so counts toward its usage.
        public var mayHaveReachedProvider: Bool {
            switch self {
            case .success, .httpError, .decodeError, .missingData, .networkError, .cancelled: true
            case .missingCredentials, .locationUnavailable, .skippedBudget, .notSent: false
            }
        }
    }

    public struct Hour: Sendable, Equatable {
        public var hourStart: Date
        public var indexes: [SchemaV2.AirQualityIndexReading]?
        public var pollutants: [SchemaV2.PollutantConcentration]?

        public init(hourStart: Date, indexes: [SchemaV2.AirQualityIndexReading]?,
                    pollutants: [SchemaV2.PollutantConcentration]?) {
            self.hourStart = hourStart
            self.indexes = indexes
            self.pollutants = pollutants
        }
    }

    public var id: UUID
    public var provider: String
    public var requestKind: String
    public var requestedAt: Date
    public var timeZoneID: String
    public var status: Status
    public var parserVersion: Int
    public var appVersion: String
    public var receivedAt: Date?
    public var failureDetail: String?
    public var httpStatus: Int?
    public var latitude: Double?
    public var longitude: Double?
    public var coordinateDecimals: Int?
    public var requestParameters: String?
    public var pageIndex: Int?
    public var rawResponse: Data?

    public var aqi: Int?
    public var dominantPollutant: String?
    public var stationName: String?
    public var stationIdx: Int?
    public var stationLatitude: Double?
    public var stationLongitude: Double?
    public var observedAtISO: String?
    public var observedTimeZone: String?
    public var subIndices: [String: Double]?

    public var forecastDate: String?
    public var pollenTypes: [SchemaV2.PollenIndexReading]?
    public var plants: [SchemaV2.PollenIndexReading]?

    public var hours: [Hour] = []

    public init(id: UUID = UUID(), provider: String, requestKind: String, requestedAt: Date, timeZoneID: String,
                status: Status, parserVersion: Int, appVersion: String) {
        self.id = id
        self.provider = provider
        self.requestKind = requestKind
        self.requestedAt = requestedAt
        self.timeZoneID = timeZoneID
        self.status = status
        self.parserVersion = parserVersion
        self.appVersion = appVersion
    }
}

public struct DailyRecordSnapshot: Sendable, Equatable {
    public let dayKey: String
    public let dayStart: Date
    public let dayEnd: Date
    public let timeZoneID: String
    public let firstSeenAt: Date

    public init(dayKey: String, dayStart: Date, dayEnd: Date, timeZoneID: String, firstSeenAt: Date) {
        self.dayKey = dayKey
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.timeZoneID = timeZoneID
        self.firstSeenAt = firstSeenAt
    }
}
