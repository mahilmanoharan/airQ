import Foundation

// Provider response parsing for `HTTPAirQualityClient`: the result type, the parsers and the
// private wire DTOs. Split out of the client so transport and parsing can change independently.

enum ParseResult<Value> {
    case reading(Value, ProviderAttempt.Parsed)
    /// A readable response without a usable reading; whatever was parsed is still recorded.
    case noReading(ProviderAttempt.Parsed?, AirQualityServiceError)
}

extension HTTPAirQualityClient {
    static func parseWAQI(_ data: Data) throws -> ParseResult<AirQualityReading> {
        let response = try JSONDecoder().decode(WAQIResponse.self, from: data)
        guard response.status == "ok", let payload = response.data else { return .noReading(nil, .missingData) }
        let geo = payload.city?.geo ?? []
        let observation = WAQIObservation(
            aqi: payload.aqi?.value, dominantPollutant: payload.dominentpol, stationName: payload.city?.name,
            stationIdx: payload.idx?.value,
            stationCoordinate: geo.count == 2 ? GeoCoordinate(latitude: geo[0], longitude: geo[1]) : nil,
            observedAtISO: payload.time?.iso, observedTimeZone: payload.time?.tz,
            subIndices: (payload.iaqi ?? [:]).compactMapValues(\.v))
        guard let aqi = observation.aqi, aqi >= 0 else { return .noReading(.waqi(observation), .missingData) }
        let daily = (payload.forecast?.value?.daily ?? [:]).mapValues { items in
            items.compactMap { item -> (day: String, min: Int, average: Int, max: Int)? in
                guard let day = item.day, let min = item.min?.value, let avg = item.avg?.value,
                      let max = item.max?.value else { return nil }
                return (day, min, avg, max)
            }
        }
        return .reading(AirQualityReading(aqi: aqi, dominantPollutant: payload.dominentpol,
                                          stationName: payload.city?.name ?? "",
                                          subIndices: observation.subIndices,
                                          forecast: AirQualityForecastDay.days(fromDaily: daily),
                                          attributions: attributions(payload),
                                          station: StationInfo(
                                            name: payload.city?.name ?? "",
                                            coordinate: observation.stationCoordinate,
                                            observedAt: payload.time?.iso.flatMap { try? Date($0, strategy: .iso8601) })),
                        .waqi(observation))
    }

    private static func attributions(_ payload: WAQIResponse.Payload) -> [DataAttribution] {
        var seen: Set<String> = []
        return (payload.attributions?.value ?? []).compactMap { item in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  seen.insert(name).inserted else { return nil }
            return DataAttribution(name: name, url: item.url.flatMap(URL.init(string:)))
        }
    }

    static func parsePollen(_ data: Data) throws -> ParseResult<PollenReading> {
        let response = try JSONDecoder().decode(PollenResponse.self, from: data)
        guard let first = response.dailyInfo?.first, let day = first.value else { return .noReading(nil, .missingData) }
        let forecast = PollenForecast(date: day.date?.key, types: (day.pollenTypeInfo ?? []).compactMap { $0.value?.value },
                                      plants: (day.plantInfo ?? []).compactMap { $0.value?.value })
        func upi(_ code: String, in types: [PollenIndexValue]) -> Int? { types.first { $0.code == code }?.upi }
        let today = [upi("GRASS", in: forecast.types), upi("TREE", in: forecast.types), upi("WEED", in: forecast.types)]
        guard today.contains(where: { $0 != nil }) else { return .noReading(.pollen(forecast), .missingData) }
        guard today.compactMap(\.self).allSatisfy({ (0...5).contains($0) }) else {
            return .noReading(.pollen(forecast), .invalidResponse)
        }
        let plants = forecast.plants.compactMap { plant -> PollenPlant? in
            guard let index = plant.upi, (0...5).contains(index) else { return nil }
            return PollenPlant(code: plant.code, name: plant.displayName ?? plant.code.capitalized, index: index,
                               inSeason: plant.inSeason)
        }
        .sorted { ($0.index, $1.name) > ($1.index, $0.name) }
        // Later days only feed the outlook; an out-of-range value there is dropped, not fatal.
        let outlook = (response.dailyInfo ?? []).dropFirst().map { entry -> PollenOutlookDay in
            // A malformed later day keeps its place (as an empty day) so the days after it stay dated right.
            let types = (entry.value?.pollenTypeInfo ?? []).compactMap { $0.value?.value }
            func valid(_ code: String) -> Int? { upi(code, in: types).flatMap { (0...5).contains($0) ? $0 : nil } }
            return PollenOutlookDay(grassIndex: valid("GRASS"), treeIndex: valid("TREE"), weedIndex: valid("WEED"))
        }
        let reading = PollenReading(grassIndex: today[0], treeIndex: today[1], weedIndex: today[2],
                                    plants: plants, outlook: Array(outlook), firstDayKey: forecast.date)
        return .reading(reading, .pollen(forecast))
    }

    static func parseHistory(_ data: Data) throws -> ParseResult<AirQualityHistoryPage> {
        let response = try JSONDecoder().decode(HistoryResponse.self, from: data)
        let hours = (response.hoursInfo ?? []).compactMap { entry -> AirQualityHour? in
            guard let hour = entry.value, let start = try? Date(hour.dateTime, strategy: .iso8601) else { return nil }
            return AirQualityHour(
                hourStart: start,
                indexes: (hour.indexes ?? []).map {
                    AirQualityIndexValue(code: $0.code, aqi: $0.aqi, category: $0.category,
                                         dominantPollutant: $0.dominantPollutant)
                },
                pollutants: (hour.pollutants ?? []).map {
                    PollutantValue(code: $0.code, value: $0.concentration?.value, units: $0.concentration?.units)
                })
        }
        return .reading(AirQualityHistoryPage(hours: hours, nextPageToken: response.nextPageToken), .hourly(hours))
    }

    /// The provider's own explanation, from Google's `error.message` or WAQI's error `data` string.
    static func providerMessage(in data: Data) -> String? {
        if let google = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data), let message = google.error?.message {
            return message
        }
        if let waqi = try? JSONDecoder().decode(WAQIErrorResponse.self, from: data), waqi.status == "error" {
            return waqi.data
        }
        return nil
    }
}

/// Decodes `Value` when it can and yields nil otherwise, instead of failing the enclosing payload.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}

/// WAQI reports "-" instead of a number when a station has no current value.
private struct LenientInt: Decodable {
    let value: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = Int(exactly: double) }
        else { value = nil }
    }
}

private struct WAQIResponse: Decodable {
    struct Payload: Decodable {
        struct City: Decodable {
            let name: String?
            let geo: [Double]?
        }
        struct Time: Decodable {
            let tz: String?
            let iso: String?
        }
        struct Value: Decodable { let v: Double? }
        struct Attribution: Decodable {
            let name: String?
            let url: String?
        }
        struct Forecast: Decodable {
            struct Item: Decodable {
                let day: String?
                let min: LenientInt?
                let avg: LenientInt?
                let max: LenientInt?
            }
            let daily: [String: [Item]]?
        }

        let aqi: LenientInt?
        let idx: LenientInt?
        let dominentpol: String?
        let city: City?
        let time: Time?
        let iaqi: [String: Value]?
        /// Optional extra: a malformed forecast must not cost the current reading.
        let forecast: Lenient<Forecast>?
        let attributions: Lenient<[Attribution]>?
    }

    let status: String
    let data: Payload?

    private enum CodingKeys: String, CodingKey { case status, data }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        // An error response carries a message string in `data` instead of a payload.
        data = status == "ok" ? try container.decode(Payload.self, forKey: .data) : nil
    }
}

private struct WAQIErrorResponse: Decodable {
    let status: String?
    let data: String?
}

private struct GoogleErrorResponse: Decodable {
    struct Body: Decodable { let message: String? }
    let error: Body?
}

private struct PollenResponse: Decodable {
    struct CalendarDate: Decodable {
        let year: Int?
        let month: Int?
        let day: Int?

        var key: String? {
            guard let year, let month, let day else { return nil }
            return DayKey.key(year: year, month: month, day: day)
        }
    }
    struct Entry: Decodable {
        struct Index: Decodable {
            let value: Int?
            let category: String?
        }
        let code: String
        let displayName: String?
        let inSeason: Bool?
        let indexInfo: Index?

        var value: PollenIndexValue {
            PollenIndexValue(code: code, displayName: displayName, upi: indexInfo?.value,
                             category: indexInfo?.category, inSeason: inSeason)
        }
    }
    struct Day: Decodable {
        let date: CalendarDate?
        /// One entry without a code must not cost the whole (billed) response.
        let pollenTypeInfo: [Lenient<Entry>]?
        let plantInfo: [Lenient<Entry>]?
    }
    let dailyInfo: [Lenient<Day>]?
}

struct HistoryRequest: Encodable {
    struct Location: Encodable {
        let latitude: Double
        let longitude: Double
    }
    let location: Location
    let hours: Int
    let pageSize: Int
    let pageToken: String?
    let universalAqi: Bool
    let extraComputations: [String]
    let languageCode: String
}

private struct HistoryResponse: Decodable {
    struct Hour: Decodable {
        struct Index: Decodable {
            let code: String
            let aqi: Int?
            let category: String?
            let dominantPollutant: String?
        }
        struct Pollutant: Decodable {
            struct Concentration: Decodable {
                let value: Double?
                let units: String?
            }
            let code: String
            let concentration: Concentration?
        }
        let dateTime: String
        let indexes: [Index]?
        let pollutants: [Pollutant]?
    }
    /// One malformed hour must not discard the page's readable ones.
    let hoursInfo: [Lenient<Hour>]?
    let nextPageToken: String?
}
