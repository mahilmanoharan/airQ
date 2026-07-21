import Foundation

/// The minimal data shared between the main app and the widget extension via the App Group.
public struct AQSnapshot: Codable, Sendable, Equatable {
    public let aqi: Int
    public let locationName: String
    public let lastUpdated: Date

    public init(aqi: Int, locationName: String, lastUpdated: Date) {
        self.aqi = aqi
        self.locationName = locationName
        self.lastUpdated = lastUpdated
    }
}
