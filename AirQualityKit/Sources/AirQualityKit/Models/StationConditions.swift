import Foundation

/// A WAQI station's `iaqi` values split into pollutants and weather. Pollutant values are
/// per-pollutant AQI sub-indices on the same scale as the headline AQI, **not** concentrations
/// (µg/m³ or ppb); weather values are the station's raw readings.
public struct StationConditions: Codable, Sendable, Equatable {
    public struct Pollutant: Codable, Sendable, Equatable, Identifiable {
        public let code: String
        public let subIndex: Int
        public var id: String { code }

        public var displayName: String { StationConditions.displayName(for: code) }
    }

    private static let names = ["pm25": "PM2.5", "pm10": "PM10", "o3": "O₃", "no2": "NO₂", "so2": "SO₂", "co": "CO"]

    /// A readable name for a WAQI pollutant code ("pm25" → "PM2.5"); unknown codes are uppercased.
    public static func displayName(for code: String) -> String { names[code] ?? code.uppercased() }

    /// Display order: particulates first, then gases. Only codes the station reported appear.
    public static let pollutantOrder = ["pm25", "pm10", "o3", "no2", "so2", "co"]

    public let pollutants: [Pollutant]
    public let temperatureCelsius: Double?
    public let humidityPercent: Double?
    public let pressureHectopascals: Double?
    public let windMetersPerSecond: Double?
    public let dewPointCelsius: Double?
    /// WAQI `wg`. Optional so snapshots written before it existed still decode.
    public let windGustMetersPerSecond: Double?

    public init(subIndices: [String: Double]) {
        pollutants = Self.pollutantOrder.compactMap { code in
            guard let value = subIndices[code], value.isFinite, value >= 0 else { return nil }
            return Pollutant(code: code, subIndex: Int(value.rounded()))
        }
        temperatureCelsius = subIndices["t"]
        humidityPercent = subIndices["h"]
        pressureHectopascals = subIndices["p"]
        windMetersPerSecond = subIndices["w"]
        dewPointCelsius = subIndices["dew"]
        windGustMetersPerSecond = subIndices["wg"]
    }

    public var hasWeather: Bool {
        [temperatureCelsius, humidityPercent, pressureHectopascals, windMetersPerSecond, dewPointCelsius,
         windGustMetersPerSecond].contains { $0 != nil }
    }

    public var isEmpty: Bool { pollutants.isEmpty && !hasWeather }
}
