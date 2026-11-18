import Foundation

/// Parsed environmental values for charting, without raw bodies.
public struct EnvironmentSeries: Sendable, Equatable {
    public struct AQIPoint: Sendable, Equatable {
        public let date: Date
        public let value: Int
        /// "waqi" (station observation) or an hourly index code such as "usa_epa".
        public let source: String
        /// Coordinates of the request that supplied this history, not the person's location that hour.
        public var place: RecordPlace? = nil
    }

    public struct PollenReading: Sendable, Equatable {
        public let requestedAt: Date
        public let code: String
        public let upi: Int
        /// Provider calendar date. Legacy entries without one fall back to the local request day.
        public var forecastDate: String? = nil
    }

    public let waqi: [AQIPoint]
    public let hourly: [AQIPoint]
    public let pollen: [PollenReading]
    /// Days (keyed by request time zone) with at least one successful provider attempt.
    public let successDayKeys: Set<String>

    public init(waqi: [AQIPoint], hourly: [AQIPoint], pollen: [PollenReading], successDayKeys: Set<String>) {
        self.waqi = waqi
        self.hourly = hourly
        self.pollen = pollen
        self.successDayKeys = successDayKeys
    }
}

/// Everything the descriptive chart draws, on one shared x-domain. No composite scores: each
/// series is a stored component or a named read-time count.
public struct ChartData: Sendable, Equatable {
    public enum DayStatus: String, Sendable { case notCollected, collectedNoData, collected }

    public struct Day: Sendable, Equatable, Identifiable {
        public let dayKey: String
        public let interval: DateInterval
        public let status: DayStatus
        public var id: String { dayKey }
    }

    public struct PollenBar: Sendable, Equatable {
        public let day: Date
        public let code: String
        public let upi: Int
    }

    public struct DetectionBar: Sendable, Equatable {
        public let day: Date
        public let count: Int
        public let listeningSeconds: TimeInterval
    }

    /// One local hour of the day (0–23) summed over the whole domain: the detected events that
    /// fell in it and how long listening was on. Counts alone would mislead (nights listened
    /// versus days listened), so exposure is always carried beside them.
    public struct HourBin: Sendable, Equatable, Identifiable {
        public let hour: Int
        public let count: Int
        public let listeningSeconds: TimeInterval
        public var id: Int { hour }
    }

    public struct CheckInPoint: Sendable, Equatable {
        public let day: Date
        /// 0 = no daytime symptoms, 1–3 = severity; nil when symptoms were yes without a severity.
        public let severity: Int?
        public let daytimeSymptoms: Bool?
        public let nightWaking: Bool?
        public let rescueInhalerUses: Int?
        /// `CheckInQuestionSet.ControllerAdherence` raw value; nil = not answered or not asked.
        public let controllerAdherence: String?
        /// The day's saved peak-flow reading in L/min, from the person's own meter.
        public var peakFlowLPM: Int? = nil
    }

    /// A resolved context event as a span of whole local days, clipped to the domain.
    public struct ContextSpan: Sendable, Equatable, Identifiable {
        /// The event chain's original id, stable across edits.
        public let id: UUID
        public let category: String
        public let note: String
        public let start: Date
        /// Exclusive: the end of the last local day, or the domain end while ongoing.
        public let end: Date
        /// No end date and the category means ongoing.
        public let isOngoing: Bool
        /// Original recorded dates, independent of clipping used to draw this span.
        public var originalStartDayKey: String? = nil
        public var originalEndDayKey: String? = nil
    }

    public let domain: DateInterval
    public let days: [Day]
    public let waqi: [EnvironmentSeries.AQIPoint]
    public let hourly: [EnvironmentSeries.AQIPoint]
    public let pollen: [PollenBar]
    public let detections: [DetectionBar]
    public let checkIns: [CheckInPoint]
    public let context: [ContextSpan]
    public let detectionLabel: String
    /// Always 24 bins, hour 0 first, in the local time zone the chart was built for.
    public let hourOfDay: [HourBin]
    /// Coverage before overlapping histories from different areas were excluded.
    public var airCoverage: AirCoverage? = nil

    /// Whether any hour has an event or listening time (otherwise there is nothing to show).
    public var hasHourOfDayData: Bool { hourOfDay.contains { $0.count > 0 || $0.listeningSeconds > 0 } }
}

/// Stored place histories describe environmental coverage, never personal exposure.
public struct AirCoverage: Sendable, Equatable {
    public let storedHours: Int
    public let ambiguousHours: Int
    public let places: [RecordPlace]
    public let unknownPlaceHours: Int

    /// Keep an hour only when its values belong to one area. An unknown place mixed with a
    /// known place is ambiguous too; legacy hours with only unknown places remain identified as such.
    static func resolve(_ hourly: [EnvironmentSeries.AQIPoint])
        -> (points: [EnvironmentSeries.AQIPoint], coverage: AirCoverage) {
        let byHour = Dictionary(grouping: hourly, by: \.date)
        var places: [RecordPlace] = []
        for place in hourly.compactMap(\.place).sorted(by: { ($0.latitude, $0.longitude) < ($1.latitude, $1.longitude) }) {
            if !places.contains(where: { $0.kilometres(to: place) <= RecordPlace.sameAreaKilometres }) { places.append(place) }
        }
        var points: [EnvironmentSeries.AQIPoint] = []
        var ambiguous = 0
        var unknown = 0
        for date in byHour.keys.sorted() {
            let values = byHour[date] ?? []
            let known = values.compactMap(\.place)
            let hasUnknown = known.count < values.count
            if hasUnknown { unknown += 1 }
            let mixed = (hasUnknown && !known.isEmpty) || known.contains { a in
                known.contains { b in a.kilometres(to: b) > RecordPlace.sameAreaKilometres }
            }
            if mixed { ambiguous += 1; continue }
            if let point = values.max(by: { $0.value < $1.value }) { points.append(point) }
        }
        return (points, AirCoverage(storedHours: byHour.count, ambiguousHours: ambiguous,
                                    places: places, unknownPlaceHours: unknown))
    }
}
