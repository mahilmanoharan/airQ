import Foundation

public enum EnvironmentalProvider: String, Sendable, CaseIterable {
    case waqi, googlePollen, googleAirQuality
}

/// One provider request attempt, success or failure, with the verbatim response body. The app
/// persists every attempt so gaps in the environmental record are explained, never silent.
public struct ProviderAttempt: Sendable, Equatable {
    public enum Status: String, Sendable {
        case success, httpError, decodeError, missingData, networkError, missingCredentials, cancelled
        case locationUnavailable, skippedBudget
        /// The request provably never left the device (offline, DNS or connect failure, invalid URL).
        case notSent
    }

    public enum Parsed: Sendable, Equatable {
        case waqi(WAQIObservation)
        case pollen(PollenForecast)
        case hourly([AirQualityHour])
    }

    public var provider: EnvironmentalProvider
    public var requestKind: String
    public var requestedAt: Date
    public var status: Status
    public var parserVersion: Int
    public var receivedAt: Date?
    public var failureDetail: String?
    public var httpStatus: Int?
    /// The coordinate actually sent to the provider, after rounding.
    public var coordinate: GeoCoordinate?
    public var coordinateDecimals: Int?
    /// Non-secret request parameters as JSON text. Never contains credentials.
    public var requestParameters: String?
    public var pageIndex: Int?
    public var rawResponse: Data?
    public var parsed: Parsed?

    public init(provider: EnvironmentalProvider, requestKind: String, requestedAt: Date,
                status: Status, parserVersion: Int) {
        self.provider = provider
        self.requestKind = requestKind
        self.requestedAt = requestedAt
        self.status = status
        self.parserVersion = parserVersion
    }

    /// An attempt that never reached the provider (location unavailable, budget reached).
    public static func notSent(_ provider: EnvironmentalProvider, requestKind: String, at date: Date,
                               status: Status, detail: String?) -> ProviderAttempt {
        var attempt = ProviderAttempt(provider: provider, requestKind: requestKind, requestedAt: date,
                                      status: status, parserVersion: 0)
        attempt.failureDetail = detail
        return attempt
    }
}

/// The WAQI feed as returned. `subIndices` are per-pollutant AQI sub-indices (and WAQI's weather
/// fields t/h/p/w), not concentrations.
public struct WAQIObservation: Sendable, Equatable {
    public var aqi: Int?
    public var dominantPollutant: String?
    public var stationName: String?
    public var stationIdx: Int?
    public var stationCoordinate: GeoCoordinate?
    public var observedAtISO: String?
    public var observedTimeZone: String?
    public var subIndices: [String: Double]

    public init(aqi: Int?, dominantPollutant: String?, stationName: String?, stationIdx: Int?,
                stationCoordinate: GeoCoordinate?, observedAtISO: String?, observedTimeZone: String?,
                subIndices: [String: Double]) {
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.stationName = stationName
        self.stationIdx = stationIdx
        self.stationCoordinate = stationCoordinate
        self.observedAtISO = observedAtISO
        self.observedTimeZone = observedTimeZone
        self.subIndices = subIndices
    }
}

/// Google's pollen forecast for one day. Values are forecasts on the 0–5 Universal Pollen Index.
public struct PollenForecast: Sendable, Equatable {
    public var date: String?
    public var types: [PollenIndexValue]
    public var plants: [PollenIndexValue]

    public init(date: String?, types: [PollenIndexValue], plants: [PollenIndexValue]) {
        self.date = date
        self.types = types
        self.plants = plants
    }
}

/// One pollen type or plant; nil fields were absent from the response (never a stand-in for 0).
public struct PollenIndexValue: Sendable, Equatable {
    public var code: String
    public var displayName: String?
    public var upi: Int?
    public var category: String?
    public var inSeason: Bool?

    public init(code: String, displayName: String?, upi: Int?, category: String?, inSeason: Bool?) {
        self.code = code
        self.displayName = displayName
        self.upi = upi
        self.category = category
        self.inSeason = inSeason
    }
}

public struct AirQualityHour: Sendable, Equatable {
    public var hourStart: Date
    public var indexes: [AirQualityIndexValue]
    public var pollutants: [PollutantValue]

    public init(hourStart: Date, indexes: [AirQualityIndexValue], pollutants: [PollutantValue]) {
        self.hourStart = hourStart
        self.indexes = indexes
        self.pollutants = pollutants
    }
}

public struct AirQualityIndexValue: Sendable, Equatable {
    public var code: String
    public var aqi: Int?
    public var category: String?
    public var dominantPollutant: String?

    public init(code: String, aqi: Int?, category: String?, dominantPollutant: String?) {
        self.code = code
        self.aqi = aqi
        self.category = category
        self.dominantPollutant = dominantPollutant
    }
}

public struct PollutantValue: Sendable, Equatable {
    public var code: String
    public var value: Double?
    public var units: String?

    public init(code: String, value: Double?, units: String?) {
        self.code = code
        self.value = value
        self.units = units
    }
}

/// A parsed value plus the attempt that produced it.
public struct Fetched<Value: Sendable>: Sendable {
    public let value: Value
    public let attempt: ProviderAttempt

    public init(value: Value, attempt: ProviderAttempt) {
        self.value = value
        self.attempt = attempt
    }
}

/// A failed attempt. The attempt is still recorded; `underlying` explains it to the user.
public struct ProviderFailure: LocalizedError, Sendable {
    public let attempt: ProviderAttempt
    public let underlying: any Error & Sendable

    public init(attempt: ProviderAttempt, underlying: any Error & Sendable) {
        self.attempt = attempt
        self.underlying = underlying
    }

    public var isCancellation: Bool { attempt.status == .cancelled }
    public var errorDescription: String? { underlying.localizedDescription }
}
