import Foundation

/// The user's opt-ins for "air quality is unhealthy" and "pollen is high" notifications. A nil
/// threshold means that alert is off; both are off by default.
public struct AirQualityAlertSettings: Codable, Sendable, Equatable {
    /// AQI values an alert can be asked for: the start of Moderate, Unhealthy for Sensitive Groups
    /// and Unhealthy.
    public static let airThresholds = [51, 101, 151]
    public static let defaultAirThreshold = 101
    /// Universal Pollen Index values (0–5): Low, Moderate and High.
    public static let pollenThresholds = [2, 3, 4]
    public static let defaultPollenThreshold = 3

    public var airThreshold: Int?
    public var pollenThreshold: Int?

    public init(airThreshold: Int? = nil, pollenThreshold: Int? = nil) {
        self.airThreshold = airThreshold
        self.pollenThreshold = pollenThreshold
    }

    public var isAnyEnabled: Bool { airThreshold != nil || pollenThreshold != nil }
}

public enum AirQualityAlertKind: String, Codable, Sendable, CaseIterable {
    case air, pollen
}

public struct AirQualityAlertContent: Sendable, Equatable {
    public let kind: AirQualityAlertKind
    public let title: String
    public let body: String
}

/// Decides which notifications a reading warrants. Pure, so the rules are tested without any
/// notification machinery. Each kind is independent: the reading must be current and at or above
/// its threshold, and a kind alerts at most once per local day (a day of bad air is one alert, not
/// one per refresh). Pollen counts as current when it was requested today, since it's a daily forecast.
/// Nothing is sent overnight: a background refresh can run at any hour, and a held alert isn't recorded,
/// so the first refresh from the end of quiet hours sends it if the reading is still current.
public enum AirQualityAlertPolicy {
    /// Local hours with no alerts: from `quietHours.start` up to (not including) `quietHours.end`, over midnight.
    public static let quietHours = (start: 22, end: 7)

    public static func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietHours.start || hour < quietHours.end
    }

    public static func alerts(for snapshot: AQSnapshot?, settings: AirQualityAlertSettings,
                              lastAlertAt: [AirQualityAlertKind: Date], now: Date = Date(),
                              calendar: Calendar = .current) -> [AirQualityAlertContent] {
        guard let snapshot, !isQuiet(now, calendar: calendar) else { return [] }
        func alreadySentToday(_ kind: AirQualityAlertKind) -> Bool {
            lastAlertAt[kind].map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
        var result: [AirQualityAlertContent] = []

        if let threshold = settings.airThreshold, snapshot.isFresh(asOf: now), snapshot.aqi >= threshold,
           !alreadySentToday(.air) {
            var body = "AQI \(snapshot.aqi) in \(snapshot.locationName): \(AirQualityPresentation.category(for: snapshot.aqi))."
            if let code = snapshot.dominantPollutant, let name = AirQualitySummary.spokenNames[code] {
                body += " Mainly \(name)."
            }
            body += " " + AirQualityPresentation.guidance(for: snapshot.aqi)
            result.append(.init(kind: .air, title: "Air quality alert", body: body))
        }

        if let threshold = settings.pollenThreshold, let index = snapshot.pollenIndex, index >= threshold,
           let fetched = snapshot.pollenFetchedAt, calendar.isDate(fetched, inSameDayAs: now),
           !alreadySentToday(.pollen) {
            let body = "Pollen is \(PollenPresentation.category(for: index).lowercased()) in \(snapshot.locationName). "
                + PollenPresentation.guidance(for: index)
            result.append(.init(kind: .pollen, title: "Pollen alert", body: body))
        }
        return result
    }
}
