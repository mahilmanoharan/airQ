import Foundation

/// The US AQI bands a day's peak is counted in (the top bands are merged: they are rare and mean the same
/// thing for planning). Shared by the clinician summary and the symptom-days table so both count days alike.
public enum AirQualityBand: Int, Sendable, CaseIterable, Comparable {
    case good, moderate, sensitive, unhealthy

    public static func of(_ aqi: Int) -> AirQualityBand {
        switch aqi {
        case ...50: .good
        case 51...100: .moderate
        case 101...150: .sensitive
        default: .unhealthy
        }
    }

    public static func < (lhs: AirQualityBand, rhs: AirQualityBand) -> Bool { lhs.rawValue < rhs.rawValue }
}
