import Foundation

/// One local day of the outlook widget: WAQI's peak forecast sub-index and Google's pollen index,
/// either of which can be missing.
public struct OutlookDay: Sendable, Equatable, Identifiable {
    public let dayKey: String
    public let aqiPeak: Int?
    public let pollenIndex: Int?
    public var id: String { dayKey }

    public init(dayKey: String, aqiPeak: Int?, pollenIndex: Int?) {
        self.dayKey = dayKey
        self.aqiPeak = aqiPeak
        self.pollenIndex = pollenIndex
    }
}

/// A single point-in-time entry the widget can render. Deliberately has no
/// WidgetKit dependency so it (and the scheduling logic below) can be unit
/// tested with Swift Testing without touching `TimelineProvider`/`Timeline<Entry>`.
public struct AQSnapshotEntry: Sendable, Equatable {
    public let date: Date
    public let aqi: Int?
    public let dominantPollutant: String?
    public let pollenIndex: Int?
    public let locationName: String
    public let lastUpdated: Date?
    public let hasData: Bool
    /// The next local day's forecast, when the snapshot carries one.
    public let tomorrow: AirQualityForecastDay?
    /// Tomorrow's highest pollen type index from the Google outlook, when known.
    public let pollenTomorrow: Int?
    /// Today onward, merged by local day (see `TimelineScheduler.outlook`).
    public let outlook: [OutlookDay]
    /// `pollenIndex` is tomorrow's forecast: an evening fetch west of UTC gets no day for local
    /// today (Google's dates are UTC-based), so widgets label the value "tomorrow".
    public let pollenIsTomorrowsForecast: Bool

    /// The reading is at least `TimelineScheduler.staleAfter` old at `date`, so widgets flag it.
    public var isStale: Bool {
        guard let lastUpdated else { return false }
        return date.timeIntervalSince(lastUpdated) >= TimelineScheduler.staleAfter
    }

    public init(
        date: Date,
        aqi: Int?,
        dominantPollutant: String?,
        pollenIndex: Int?,
        locationName: String,
        lastUpdated: Date?,
        hasData: Bool,
        tomorrow: AirQualityForecastDay? = nil,
        pollenTomorrow: Int? = nil,
        outlook: [OutlookDay] = [],
        pollenIsTomorrowsForecast: Bool = false
    ) {
        self.date = date
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.pollenIndex = pollenIndex
        self.locationName = locationName
        self.lastUpdated = lastUpdated
        self.hasData = hasData
        self.tomorrow = tomorrow
        self.pollenTomorrow = pollenTomorrow
        self.outlook = outlook
        self.pollenIsTomorrowsForecast = pollenIsTomorrowsForecast
    }
}

public enum TimelineScheduler {
    public static let refreshInterval: TimeInterval = 60 * 60
    public static var staleAfter: TimeInterval { AQSnapshot.staleAfter }

    /// Builds the entries for a widget timeline from the last known snapshot.
    /// There's only ever one fetch source of truth (the main app), so this
    /// always produces a single "now" entry — either real data or a
    /// no-data placeholder — rather than trying to interpolate future readings.
    public static func makeEntries(from snapshot: AQSnapshot?, currentDate: Date,
                                   calendar: Calendar = .current) -> [AQSnapshotEntry] {
        guard let snapshot else {
            return [
                AQSnapshotEntry(
                    date: currentDate,
                    aqi: nil,
                    dominantPollutant: nil,
                    pollenIndex: nil,
                    locationName: "Current Location",
                    lastUpdated: nil,
                    hasData: false
                )
            ]
        }

        // Boundaries inside the next day get their own precomputed entries, so the widget flips to
        // "old" and rolls "tomorrow" over on time even when WidgetKit reloads late.
        var dates = [currentDate]
        let staleAt = snapshot.lastUpdated.addingTimeInterval(staleAfter)
        if staleAt > currentDate { dates.append(staleAt) }
        if let midnight = calendar.nextDate(after: currentDate, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                            matchingPolicy: .nextTime) {
            dates.append(midnight)
        }
        let horizon = currentDate.addingTimeInterval(24 * 60 * 60)
        return dates.filter { $0 < horizon }.sorted().map { date in
            let headline = headlinePollen(snapshot, on: date, calendar: calendar)
            return AQSnapshotEntry(
                date: date,
                aqi: snapshot.aqi,
                dominantPollutant: snapshot.dominantPollutant,
                pollenIndex: headline.index,
                locationName: snapshot.locationName,
                lastUpdated: snapshot.lastUpdated,
                hasData: true,
                tomorrow: tomorrow(in: snapshot.forecast ?? [], after: date, calendar: calendar),
                // When the headline already is tomorrow's forecast, a "tomorrow" line would repeat it.
                pollenTomorrow: headline.isTomorrow ? nil : pollenTomorrow(snapshot, after: date, calendar: calendar),
                outlook: outlook(snapshot, from: date, calendar: calendar),
                pollenIsTomorrowsForecast: headline.isTomorrow
            )
        }
    }

    /// The pollen shown as "now": the forecast for the local day of `date`, keyed by Google's own
    /// dates, so it can't contradict the "tomorrow" line. When the forecast has no day for local
    /// today but starts tomorrow (an evening fetch west of UTC), tomorrow's value is shown and
    /// flagged rather than leaving the widget empty until the next day's fetch. Without Google's
    /// dates, a forecast fetched on an earlier local day isn't today's; legacy snapshots with no
    /// fetch time keep their stored value.
    static func headlinePollen(_ snapshot: AQSnapshot, on date: Date,
                               calendar: Calendar) -> (index: Int?, isTomorrow: Bool) {
        if let pollen = snapshot.pollenTypes, let keys = pollen.dayKeys {
            let today = DayKey.local(date, in: calendar)
            if let index = pollen.overallIndex(forDayKey: today) { return (index, false) }
            if let next = calendar.date(byAdding: .day, value: 1, to: date),
               keys.first == DayKey.local(next, in: calendar), let index = pollen.overallIndex {
                return (index, true)
            }
            return (nil, false)
        }
        if let fetchedAt = snapshot.pollenFetchedAt, !calendar.isDate(fetchedAt, inSameDayAs: date) { return (nil, false) }
        return (snapshot.pollenIndex, false)
    }

    static func tomorrow(in forecast: [AirQualityForecastDay], after date: Date,
                         calendar: Calendar) -> AirQualityForecastDay? {
        guard let next = calendar.date(byAdding: .day, value: 1, to: date),
              let first = AirQualityForecastDay.upcoming(forecast, asOf: next, calendar: calendar, limit: 1).first,
              let firstDate = first.date(in: calendar), calendar.isDate(firstDate, inSameDayAs: next)
        else { return nil }
        return first
    }

    /// Keyed by Google's own forecast dates when known (they are UTC-based); otherwise outlook day
    /// `n` is taken as `n + 1` local days after the fetch.
    static func pollenTomorrow(_ snapshot: AQSnapshot, after date: Date, calendar: Calendar) -> Int? {
        if let pollen = snapshot.pollenTypes, pollen.dayKeys != nil {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            return pollen.overallIndex(forDayKey: DayKey.local(tomorrow, in: calendar))
        }
        guard let fetchedAt = snapshot.pollenFetchedAt, let outlook = snapshot.pollenTypes?.outlook else { return nil }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: fetchedAt),
                                              to: calendar.startOfDay(for: date)).day ?? -1
        guard elapsed >= 0, outlook.indices.contains(elapsed) else { return nil }
        return outlook[elapsed].overallIndex
    }

    /// The next local day's forecast peak and pollen, for planning on the dashboard; nil when neither is
    /// known. Same rules as the Outlook widget (pollen only by Google's own dates), from the saved snapshot.
    public static func tomorrow(for snapshot: AQSnapshot, now: Date = Date(), calendar: Calendar = .current) -> OutlookDay? {
        guard let next = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return outlook(snapshot, from: next, calendar: calendar, days: 1).first
    }

    /// Up to `days` local days from today: a day appears when either source has a value for it.
    /// Pollen is only taken from Google's own dates (never guessed from the fetch day).
    static func outlook(_ snapshot: AQSnapshot, from date: Date, calendar: Calendar, days: Int = 4) -> [OutlookDay] {
        let forecast = Dictionary((snapshot.forecast ?? []).map { ($0.day, $0.peak?.subIndex) },
                                  uniquingKeysWith: { first, _ in first })
        return (0..<days).compactMap { offset -> OutlookDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
            let key = DayKey.local(day, in: calendar)
            let aqi = forecast[key] ?? nil
            let pollen = snapshot.pollenTypes?.overallIndex(forDayKey: key)
            guard aqi != nil || pollen != nil else { return nil }
            return OutlookDay(dayKey: key, aqiPeak: aqi, pollenIndex: pollen)
        }
    }

    public static func nextRefreshDate(after date: Date) -> Date {
        date.addingTimeInterval(refreshInterval)
    }

    /// The earliest of the regular refresh, the moment the reading turns stale, and the next local
    /// midnight (when "tomorrow" becomes today), so the widget never shows either a boundary late.
    public static func nextRefreshDate(after date: Date, snapshot: AQSnapshot?, calendar: Calendar = .current) -> Date {
        var candidates = [nextRefreshDate(after: date)]
        if let snapshot {
            let staleAt = snapshot.lastUpdated.addingTimeInterval(staleAfter)
            if staleAt > date { candidates.append(staleAt) }
        }
        if let midnight = calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                            matchingPolicy: .nextTime) {
            candidates.append(midnight)
        }
        return candidates.min() ?? nextRefreshDate(after: date)
    }
}
