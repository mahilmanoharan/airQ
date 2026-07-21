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

public enum PollenPresentation {
    public static func color(for count: Int) -> Color {
        switch count {
        case 0...14:
            return .green
        case 15...89:
            return .orange
        case 90...1499:
            return .red
        default:
            return .yellow
        }
    }

    public static func category(for count: Int) -> String {
        switch count {
        case 0...14:
            return "Low"
        case 15...89:
            return "Moderate"
        case 90...1499:
            return "High"
        default:
            return "Very High"
        }
    }

    public static func guidance(for count: Int) -> String {
        switch count {
        case 0...14:
            return "Pollen levels are low to none, run free!"
        case 15...89:
            return "Medium pollen leves. Wear mask if sensitive, otherwise proceed with caution"
        case 90...1499:
            return "High pollen levels. Definitely wear a mask and proceed with extreme caution or any necessary measures."
        default:
            return "Health warning of emergency conditions. Everyone should avoid all outdoor physical activity."
        }
    }
}
