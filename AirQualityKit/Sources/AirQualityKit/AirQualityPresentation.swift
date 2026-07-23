import SwiftUI

// MARK: - AQI Presentation

public enum AirQualityPresentation {
    public static func color(for aqi: Int) -> Color {
        switch aqi {
        case 0...50:
            return .green
        case 51...100:
            return .yellow
        case 101...150:
            return .orange
        case 151...200:
            return .red
        case 201...300:
            return .purple
        default:
            return .brown
        }
    }

    public static func category(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "Good"
        case 51...100:
            return "Moderate"
        case 101...150:
            return "Unhealthy for Sensitive Groups"
        case 151...200:
            return "Unhealthy"
        case 201...300:
            return "Very Unhealthy"
        default:
            return "Hazardous"
        }
    }

    public static func guidance(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "Air quality is satisfactory, and air pollution poses little or no risk."
        case 51...100:
            return "Air quality is acceptable. However, there may be a risk for some people who are unusually sensitive to air pollution."
        case 101...150:
            return "Members of sensitive groups may experience health effects. Use caution during outdoor activities."
        case 151...200:
            return "Some members of the general public may experience health effects. Avoid strenuous outdoor activity."
        case 201...300:
            return "Health alert: The risk of health effects is increased for everyone. Avoid outdoor activities."
        default:
            return "Health warning of emergency conditions. Everyone should avoid all outdoor physical activity."
        }
    }
}

// MARK: - Pollen Presentation

/// Keyed on Google's Universal Pollen Index (0–5), not a raw grain count.
public enum PollenPresentation {
    public static func color(for index: Int) -> Color {
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

    public static func category(for index: Int) -> String {
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

    public static func guidance(for index: Int) -> String {
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
