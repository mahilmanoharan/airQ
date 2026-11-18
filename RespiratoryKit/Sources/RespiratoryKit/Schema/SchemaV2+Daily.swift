import Foundation
import SwiftData

extension SchemaV2 {
    /// One pollen type or plant exactly as the provider returned it; nil means the field was absent.
    public struct PollenIndexReading: Codable, Sendable, Hashable {
        public var code: String
        public var displayName: String?
        public var upi: Int?
        public var category: String?
        public var inSeason: Bool?

        public init(code: String, displayName: String? = nil, upi: Int?, category: String?, inSeason: Bool?) {
            self.code = code
            self.displayName = displayName
            self.upi = upi
            self.category = category
            self.inSeason = inSeason
        }
    }

    /// One air-quality index for an hour (e.g. "uaqi", "usa_epa") exactly as returned.
    public struct AirQualityIndexReading: Codable, Sendable, Hashable {
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

    /// One pollutant concentration for an hour, with the provider's units string verbatim.
    public struct PollutantConcentration: Codable, Sendable, Hashable {
        public var code: String
        public var value: Double?
        public var units: String?

        public init(code: String, value: Double?, units: String?) {
            self.code = code
            self.value = value
            self.units = units
        }
    }

    /// One local calendar day on which the app was used: a collection opportunity. No row for a day
    /// means "not collected"; a row whose observations all failed means "collected, no data".
    /// One row per dayKey is enforced by the single store actor that creates these.
    @Model
    public final class DailyRecord {
        #Index<DailyRecord>([\.dayKey])

        public var id: UUID = UUID()
        /// Local calendar date "yyyy-MM-dd" in `timeZoneID`.
        public var dayKey: String = ""
        public var dayStart: Date = Date.distantPast
        /// Exclusive end; 23 h / 25 h on DST transition days.
        public var dayEnd: Date = Date.distantPast
        public var timeZoneID: String = ""
        public var utcOffsetAtStartSeconds: Int = 0
        public var firstSeenAt: Date = Date.distantPast
        public var appVersion: String = ""
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), dayKey: String, dayStart: Date, dayEnd: Date,
            timeZoneID: String, utcOffsetAtStartSeconds: Int, firstSeenAt: Date,
            appVersion: String, schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.dayKey = dayKey
            self.dayStart = dayStart
            self.dayEnd = dayEnd
            self.timeZoneID = timeZoneID
            self.utcOffsetAtStartSeconds = utcOffsetAtStartSeconds
            self.firstSeenAt = firstSeenAt
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }

    /// One environmental provider request attempt, including failures and skipped requests, so
    /// "no data" is always distinguishable from "not collected". `rawResponse` is the verbatim body
    /// and the ground truth; parsed fields are regenerable from it (see `parserVersion`).
    /// There is no stored daily aggregate: a day's value is a read-time function.
    @Model
    public final class EnvironmentalObservation {
        #Index<EnvironmentalObservation>([\.provider, \.requestedAt], [\.requestedAt])

        public var id: UUID = UUID()
        public var provider: String = ""
        public var requestKind: String = ""
        public var requestedAt: Date = Date.distantPast
        public var receivedAt: Date?
        public var requestTimeZoneID: String = ""
        public var status: String = ""
        public var failureDetail: String?
        public var httpStatus: Int?
        /// The coordinate sent to the provider (after rounding), i.e. where exposure was queried.
        public var requestLatitude: Double?
        public var requestLongitude: Double?
        public var coordinateDecimals: Int?
        /// Non-secret request parameters as JSON text (never credentials).
        public var requestParameters: String?
        public var pageIndex: Int?
        @Attribute(.externalStorage) public var rawResponse: Data?
        public var parserVersion: Int = 0

        // WAQI feed, as returned. `subIndices` are per-pollutant AQI sub-indices (plus WAQI's
        // weather fields t/h/p/w), not concentrations.
        public var aqi: Int?
        public var dominantPollutant: String?
        public var stationName: String?
        public var stationIdx: Int?
        public var stationLatitude: Double?
        public var stationLongitude: Double?
        public var observedAtISO: String?
        public var observedTimeZone: String?
        public var subIndices: [String: Double]?

        // Google Pollen forecast, as returned. Values are forecasts, not measurements.
        public var forecastDate: String?
        public var pollenTypes: [PollenIndexReading]?
        public var plants: [PollenIndexReading]?

        public var appVersion: String = ""
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), provider: String, requestKind: String, requestedAt: Date,
            requestTimeZoneID: String, status: String, parserVersion: Int,
            appVersion: String, schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.provider = provider
            self.requestKind = requestKind
            self.requestedAt = requestedAt
            self.requestTimeZoneID = requestTimeZoneID
            self.status = status
            self.parserVersion = parserVersion
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }

    /// One hour from an hourly air-quality response, tied to the request (`observationID`) that
    /// returned it. Overlapping requests keep every row; de-duplication happens at read time.
    @Model
    public final class HourlyAirQuality {
        #Index<HourlyAirQuality>([\.provider, \.hourStart], [\.observationID])

        public var id: UUID = UUID()
        public var observationID: UUID = UUID()
        public var provider: String = ""
        public var hourStart: Date = Date.distantPast
        public var indexes: [AirQualityIndexReading]?
        public var pollutants: [PollutantConcentration]?
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), observationID: UUID, provider: String, hourStart: Date,
            indexes: [AirQualityIndexReading]?, pollutants: [PollutantConcentration]?,
            schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.observationID = observationID
            self.provider = provider
            self.hourStart = hourStart
            self.indexes = indexes
            self.pollutants = pollutants
            self.schemaVersion = schemaVersion
        }
    }

    /// Append-only daily check-in: re-saving creates a new row and the latest per `dayKey` wins at
    /// read time. Same-day vs backfilled is derived from `recordedAt`, never stored. Every answer is
    /// optional so "unanswered" is never recorded as "no".
    @Model
    public final class DailyCheckIn {
        #Index<DailyCheckIn>([\.dayKey], [\.recordedAt])

        public var id: UUID = UUID()
        /// The local day being described (chosen by the user), not necessarily the day recorded.
        public var dayKey: String = ""
        public var recordedAt: Date = Date.distantPast
        public var recordedTimeZoneID: String = ""
        /// Wording, scales, recall periods and chip set in force for this row.
        public var questionSetVersion: Int = 0
        public var daytimeSymptoms: Bool?
        public var daytimeSeverity: Int?
        /// About the night ending on the morning of `dayKey`.
        public var nightWaking: Bool?
        public var rescueInhalerUses: Int?
        public var activityLimited: Bool?
        public var symptomsPresented: [String] = []
        public var symptomsSelected: [String] = []
        public var windowsOpen: String?
        /// Litres per minute from a physical peak-flow meter.
        public var peakFlowLPM: Int?
        public var peakFlowMeasuredAt: Date?
        public var completionSeconds: Double?
        public var appVersion: String = ""
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), dayKey: String, recordedAt: Date, recordedTimeZoneID: String,
            questionSetVersion: Int, symptomsPresented: [String],
            appVersion: String, schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.dayKey = dayKey
            self.recordedAt = recordedAt
            self.recordedTimeZoneID = recordedTimeZoneID
            self.questionSetVersion = questionSetVersion
            self.symptomsPresented = symptomsPresented
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }

    /// A discrete event that breaks comparability across the record. Append-only: an edit is a new
    /// row with `supersedesID`; a removal is a row with `isRetraction` pointing at its target.
    @Model
    public final class ContextEvent {
        #Index<ContextEvent>([\.startDayKey], [\.recordedAt])

        public var id: UUID = UUID()
        public var category: String = ""
        public var note: String = ""
        public var startDayKey: String = ""
        public var endDayKey: String?
        public var recordedAt: Date = Date.distantPast
        public var recordedTimeZoneID: String = ""
        public var supersedesID: UUID?
        public var isRetraction: Bool = false
        public var appVersion: String = ""
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), category: String, note: String, startDayKey: String, endDayKey: String?,
            recordedAt: Date, recordedTimeZoneID: String, supersedesID: UUID? = nil, isRetraction: Bool = false,
            appVersion: String, schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.category = category
            self.note = note
            self.startDayKey = startDayKey
            self.endDayKey = endDayKey
            self.recordedAt = recordedAt
            self.recordedTimeZoneID = recordedTimeZoneID
            self.supersedesID = supersedesID
            self.isRetraction = isRetraction
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }
}
