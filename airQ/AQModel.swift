import Foundation


struct airquality: Codable{
    let status: String
    let data: Data
}

struct Data: Codable{
    let aqi: Int
    let idx: Int
    let attributions: [Attribution]
    let city: City
    let dominentpol: String
    let iaqi: IAQI
    let time: TimeData
    let forecase: Forecast
    let debug: DebugInfo
    
}

struct Attribution: Codable{
    let url: String
    let name: String
}

struct City: Codable{
    let geo: [Double]
    let name: String
    let url: String
    let location: String
}

struct IAQI: Codable{
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
}

struct IAQIValue: Codable{
    let v: Double
}

struct TimeData: Codable{
    let s: String
    let tz: String
    let v: Int
    let iso: String
}

struct Forecast: Codable{
    let daily: DailyForecast
}

struct DailyForecast: Codable{
    let o3: [ForecastItem]?
    let pm10: [ForecastItem]?
    let pm25: [ForecastItem]?
    let uvi: [ForecastItem]?
}

struct ForecastItem: Codable{
    let avg: Int
    let day: String
    let max: Int
    let min: Int
}

struct DebugInfo: Codable{
    let sync: String
}
