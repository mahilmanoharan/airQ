import Foundation

/// A one-sentence, speakable summary of a cached snapshot, for Siri/Shortcuts. It states the age of
/// the reading instead of refreshing it, so answering never makes a request.
public enum AirQualitySummary {
    /// Beyond this age the summary says the reading is old and suggests opening the app.
    public static var staleAfter: TimeInterval { AQSnapshot.staleAfter }

    static let spokenNames = [
        "pm25": "fine particles, PM 2.5", "pm10": "coarse particles, PM 10", "o3": "ozone",
        "no2": "nitrogen dioxide", "so2": "sulfur dioxide", "co": "carbon monoxide",
    ]

    public static func sentence(for snapshot: AQSnapshot?, asOf now: Date = Date()) -> String {
        guard let snapshot else { return "airQ has no reading yet. Open airQ to load air quality." }
        var sentence = "The air quality index in \(snapshot.locationName) is \(snapshot.aqi), "
            + "\(AirQualityPresentation.category(for: snapshot.aqi).lowercased())"
        // Naming the main pollutant only matters once the air is no longer Good.
        if snapshot.aqi > 50, let code = snapshot.dominantPollutant, let name = spokenNames[code] {
            sentence += ", mainly \(name)"
        }
        if let pollen = snapshot.pollenIndex {
            sentence += ", and pollen is \(PollenPresentation.category(for: pollen).lowercased())"
        }
        sentence += "."
        let age = now.timeIntervalSince(snapshot.lastUpdated)
        if age >= staleAfter {
            let hours = Int(age / 3_600)
            sentence += " That reading is \(hours) hours old; open airQ to refresh it."
        }
        return sentence
    }

    /// The summary followed by the EPA guidance for that AQI, verbatim from the category table (no
    /// advice of airQ's own). With no reading, just the "open airQ" sentence.
    public static func advice(for snapshot: AQSnapshot?, asOf now: Date = Date()) -> String {
        let summary = sentence(for: snapshot, asOf: now)
        guard let snapshot else { return summary }
        return summary + " " + AirQualityPresentation.guidance(for: snapshot.aqi)
    }
}
