import Foundation

// MARK: - Air Quality Response

public struct AirQuality: Codable, Sendable {
    public let status: String
    public let data: AQData
}

public struct AQData: Codable, Sendable {
    public let aqi: Int
    public let idx: Int
    public let attributions: [Attribution]
    public let city: City
    public let dominentpol: String?
    public let iaqi: IAQI
    public let time: TimeData
    public let forecast: Forecast?
    public let debug: DebugInfo?

    enum CodingKeys: String, CodingKey {
        case aqi, idx, attributions, city, dominentpol, iaqi, time, forecast, debug
    }
}

public struct Attribution: Codable, Sendable {
    public let url: String
    public let name: String
    public let logo: String?
}

public struct City: Codable, Sendable {
    public let geo: [Double]
    public let name: String
    public let url: String
    public let location: String?
}

public struct IAQI: Codable, Sendable {
    public let co: IAQIValue?
    public let h: IAQIValue?
    public let no2: IAQIValue?
    public let o3: IAQIValue?
    public let p: IAQIValue?
    public let pm10: IAQIValue?
    public let pm25: IAQIValue?
    public let so2: IAQIValue?
    public let t: IAQIValue?
    public let w: IAQIValue?
    public let dew: IAQIValue?
    public let wg: IAQIValue?
}

public struct IAQIValue: Codable, Sendable {
    public let v: Double
}

public struct TimeData: Codable, Sendable {
    public let s: String
    public let tz: String
    public let v: Int
    public let iso: String
}

public struct Forecast: Codable, Sendable {
    public let daily: DailyForecast
}

public struct DailyForecast: Codable, Sendable {
    public let o3: [ForecastItem]?
    public let pm10: [ForecastItem]?
    public let pm25: [ForecastItem]?
    public let uvi: [ForecastItem]?
}

public struct ForecastItem: Codable, Sendable {
    public let avg: Int
    public let day: String
    public let max: Int
    public let min: Int
}

public struct DebugInfo: Codable, Sendable {
    public let sync: String
}
