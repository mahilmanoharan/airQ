import SwiftUI

// MARK: - AQI Presentation

public enum AirQualityPresentation {
    /// One US AQI category: its inclusive index range, name, colour and guidance.
    public struct Band: Sendable {
        public let range: ClosedRange<Int>
        public let category: String
        public let color: Color
        public let guidance: String
    }

    /// The US AQI breakpoints, in order. The last band is open-ended (above 300 is Hazardous).
    public static let bands: [Band] = [
        Band(range: 0...50, category: "Good", color: .green,
             guidance: "Air quality is satisfactory, and air pollution poses little or no risk."),
        Band(range: 51...100, category: "Moderate", color: .yellow,
             guidance: "Air quality is acceptable. However, there may be a risk for some people who are unusually sensitive to air pollution."),
        Band(range: 101...150, category: "Unhealthy for Sensitive Groups", color: .orange,
             guidance: "Members of sensitive groups may experience health effects. Use caution during outdoor activities."),
        Band(range: 151...200, category: "Unhealthy", color: .red,
             guidance: "Some members of the general public may experience health effects. Avoid strenuous outdoor activity."),
        Band(range: 201...300, category: "Very Unhealthy", color: .purple,
             guidance: "Health alert: The risk of health effects is increased for everyone. Avoid outdoor activities."),
        Band(range: 301...Int.max, category: "Hazardous", color: .brown,
             guidance: "Health warning of emergency conditions. Everyone should avoid all outdoor physical activity."),
    ]

    /// The band containing `aqi`; negative values (never a valid AQI) fall in the first band.
    public static func band(for aqi: Int) -> Band {
        bands.first { $0.range.contains(aqi) } ?? bands[0]
    }

    public static func color(for aqi: Int) -> Color { band(for: aqi).color }

    public static func category(for aqi: Int) -> String { band(for: aqi).category }

    public static func guidance(for aqi: Int) -> String { band(for: aqi).guidance }
}

// MARK: - Pollen Presentation

/// Keyed on Google's Universal Pollen Index (0–5), not a raw grain count.
public enum PollenPresentation {
    public static func color(for index: Int?) -> Color {
        guard let index else { return .secondary }
        switch index {
        case 0:
            return .green
        case 1:
            return .green
        case 2:
            return .yellow
        case 3:
            return .orange
        case 4:
            return .red
        default:
            return .purple
        }
    }

    public static func category(for index: Int?) -> String {
        guard let index else { return "Unavailable" }
        switch index {
        case 0:
            return "None"
        case 1:
            return "Very Low"
        case 2:
            return "Low"
        case 3:
            return "Moderate"
        case 4:
            return "High"
        default:
            return "Very High"
        }
    }

    public static func guidance(for index: Int?) -> String {
        guard let index else { return "Pollen data is unavailable for this reading. airQ checks pollen once a day, so it may return on a later day." }
        switch index {
        case 0:
            return "No pollen detected today, run free!"
        case 1:
            return "Pollen levels are very low. Little to no risk for most people."
        case 2:
            return "Pollen levels are low. Sensitive individuals may notice mild symptoms."
        case 3:
            return "Moderate pollen levels. Wear a mask if sensitive, otherwise proceed with caution."
        case 4:
            return "High pollen levels. Consider a mask and limiting prolonged outdoor activity if sensitive."
        default:
            return "Very high pollen levels. Sensitive individuals should minimize outdoor exposure."
        }
    }
}
