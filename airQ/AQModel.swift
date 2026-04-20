import Foundation

// MARK: - Air Quality Response

struct AirQuality: Codable {
    let status: String
    let data: AQData
}

struct AQData: Codable {
    let aqi: Int
    let idx: Int
    let attributions: [Attribution]
    let city: City
    let dominentpol: String?
    let iaqi: IAQI
    let time: TimeData
    let forecast: Forecast?
    let debug: DebugInfo?
    
    enum CodingKeys: String, CodingKey {
        case aqi, idx, attributions, city, dominentpol, iaqi, time, forecast, debug
    }
}

struct Attribution: Codable {
    let url: String
    let name: String
    let logo: String?
}

struct City: Codable {
    let geo: [Double]
    let name: String
    let url: String
    let location: String?
}

struct IAQI: Codable {
    let co: IAQIValue?
    let h: IAQIValue?
    let no2: IAQIValue?
    let o3: IAQIValue?
    let p: IAQIValue?
    let pm10: IAQIValue?
    let pm25: IAQIValue?
    let so2: IAQIValue?
    let t: IAQIValue?
    let w: IAQIValue?
    let dew: IAQIValue?
    let wg: IAQIValue?
}

struct IAQIValue: Codable {
    let v: Double
}

struct TimeData: Codable {
    let s: String
    let tz: String
    let v: Int
    let iso: String
}

struct Forecast: Codable {
    let daily: DailyForecast
}

struct DailyForecast: Codable {
    let o3: [ForecastItem]?
    let pm10: [ForecastItem]?
    let pm25: [ForecastItem]?
    let uvi: [ForecastItem]?
}

struct ForecastItem: Codable {
    let avg: Int
    let day: String
    let max: Int
    let min: Int
}

struct DebugInfo: Codable {
    let sync: String
}

