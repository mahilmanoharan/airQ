import Foundation
import Testing
@testable import AirQualityKit

private let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)

@Suite("HTTP air quality client")
struct HTTPAirQualityClientTests {
    private let coordinate = GeoCoordinate(latitude: 40.12345, longitude: -74.98765)
    private let rounded = GeoCoordinate(latitude: 40.12, longitude: -74.99)

    @Test("WAQI requests send rounded coordinates and return the full attempt with the raw body")
    func airQuality() async throws {
        let body = #"{"status":"ok","data":{"aqi":42,"idx":5,"dominentpol":"pm25","city":{"name":"Test","geo":[40.1,-74.9]},"time":{"tz":"-04:00","iso":"2026-09-14T08:00:00-04:00"},"iaqi":{"pm25":{"v":42},"t":{"v":18.5}}}}"#
        let client = makeClient { request in
            #expect(request.url?.absoluteString.hasPrefix("https://api.waqi.info/feed/geo:40.12;-74.99/?") == true)
            let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(items?.contains(URLQueryItem(name: "token", value: "test-token")) == true)
            return (body, 200)
        }
        let fetched = try await client.airQuality(at: coordinate)

        #expect(fetched.value == AirQualityReading(aqi: 42, dominantPollutant: "pm25", stationName: "Test",
                                                   subIndices: ["pm25": 42, "t": 18.5],
                                                   station: StationInfo(
                                                    name: "Test", coordinate: GeoCoordinate(latitude: 40.1, longitude: -74.9),
                                                    observedAt: try Date("2026-09-14T08:00:00-04:00", strategy: .iso8601))))
        let attempt = fetched.attempt
        #expect(attempt.provider == .waqi && attempt.status == .success && attempt.httpStatus == 200)
        #expect(attempt.rawResponse == Data(body.utf8))
        #expect(attempt.coordinate == rounded && attempt.coordinateDecimals == 2)
        #expect(attempt.requestedAt == fixedNow && attempt.receivedAt == fixedNow)
        #expect(attempt.parsed == .waqi(WAQIObservation(
            aqi: 42, dominantPollutant: "pm25", stationName: "Test", stationIdx: 5,
            stationCoordinate: GeoCoordinate(latitude: 40.1, longitude: -74.9),
            observedAtISO: "2026-09-14T08:00:00-04:00", observedTimeZone: "-04:00",
            subIndices: ["pm25": 42, "t": 18.5])))
    }

    @Test("A station with no current value ('-') is missing data, but its details are still recorded")
    func dashAQI() async throws {
        let body = #"{"status":"ok","data":{"aqi":"-","idx":7,"city":{"name":"Quiet"}}}"#
        let failure = try #require(await failure { try await makeClient { _ in (body, 200) }.airQuality(at: coordinate) })
        #expect(failure.attempt.status == .missingData)
        #expect(failure.attempt.rawResponse == Data(body.utf8))
        guard case .waqi(let observation)? = failure.attempt.parsed else {
            Issue.record("Expected the parsed WAQI observation to be recorded")
            return
        }
        #expect(observation.aqi == nil && observation.stationName == "Quiet" && observation.stationIdx == 7)
    }

    @Test("A WAQI error response is missing data with its body preserved")
    func waqiError() async throws {
        let body = #"{"status":"error","data":"Unknown station"}"#
        let failure = try #require(await failure { try await makeClient { _ in (body, 200) }.airQuality(at: coordinate) })
        #expect(failure.attempt.status == .missingData)
        #expect(failure.attempt.parsed == nil)
        #expect(failure.attempt.rawResponse == Data(body.utf8))
    }

    @Test("Negative AQI values are rejected")
    func invalidReading() async throws {
        let body = #"{"status":"ok","data":{"aqi":-1,"city":{"name":"Test"}}}"#
        let failure = try #require(await failure { try await makeClient { _ in (body, 200) }.airQuality(at: coordinate) })
        #expect(failure.attempt.status == .missingData)
    }

    @Test("Pollen keeps every type and plant as returned; an absent type is nil, never zero")
    func pollen() async throws {
        let body = #"{"dailyInfo":[{"date":{"year":2026,"month":9,"day":14},"pollenTypeInfo":[{"code":"GRASS","displayName":"Grass","inSeason":true,"indexInfo":{"value":1,"category":"Very Low"}},{"code":"TREE","displayName":"Tree","inSeason":false},{"code":"WEED","indexInfo":{"value":4,"category":"High"}}],"plantInfo":[{"code":"RAGWEED","displayName":"Ragweed","inSeason":true,"indexInfo":{"value":4,"category":"High"}}]}]}"#
        let client = makeClient { request in
            #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "test.app")
            let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(items?.contains(URLQueryItem(name: "location.latitude", value: "40.12")) == true)
            #expect(items?.contains(URLQueryItem(name: "days", value: "5")) == true)
            return (body, 200)
        }
        let fetched = try await client.pollen(at: coordinate)

        #expect(fetched.value == PollenReading(grassIndex: 1, treeIndex: nil, weedIndex: 4,
                                               plants: [PollenPlant(code: "RAGWEED", name: "Ragweed", index: 4, inSeason: true)],
                                               outlook: [], firstDayKey: "2026-09-14"))
        #expect(fetched.value.overallIndex == 4)
        #expect(fetched.attempt.parsed == .pollen(PollenForecast(
            date: "2026-09-14",
            types: [
                PollenIndexValue(code: "GRASS", displayName: "Grass", upi: 1, category: "Very Low", inSeason: true),
                PollenIndexValue(code: "TREE", displayName: "Tree", upi: nil, category: nil, inSeason: false),
                PollenIndexValue(code: "WEED", displayName: nil, upi: 4, category: "High", inSeason: nil),
            ],
            plants: [PollenIndexValue(code: "RAGWEED", displayName: "Ragweed", upi: 4, category: "High", inSeason: true)])))
    }

    @Test("Later days become the outlook; plants without a value or out of range are left out, off-season ones kept")
    func pollenOutlook() async throws {
        let body = #"{"dailyInfo":["#
            + #"{"pollenTypeInfo":[{"code":"TREE","indexInfo":{"value":2}}],"plantInfo":["#
            + #"{"code":"OAK","displayName":"Oak","inSeason":true,"indexInfo":{"value":2}},"#
            + #"{"code":"BIRCH","displayName":"Birch","inSeason":false,"indexInfo":{"value":1}},"#
            + #"{"code":"PINE","displayName":"Pine","inSeason":true},"#
            + #"{"code":"ELM","inSeason":true,"indexInfo":{"value":3}},"#
            + #"{"code":"ASH","displayName":"Ash","indexInfo":{"value":7}}]},"#
            + #"{"pollenTypeInfo":[{"code":"TREE","indexInfo":{"value":3}},{"code":"GRASS","indexInfo":{"value":9}}]},"#
            + #"{}]}"#
        let fetched = try await makeClient { _ in (body, 200) }.pollen(at: coordinate)
        #expect(fetched.value.plants == [PollenPlant(code: "ELM", name: "Elm", index: 3, inSeason: true),
                                         PollenPlant(code: "OAK", name: "Oak", index: 2, inSeason: true),
                                         PollenPlant(code: "BIRCH", name: "Birch", index: 1, inSeason: false)])
        #expect(fetched.value.outlook == [PollenOutlookDay(grassIndex: nil, treeIndex: 3, weedIndex: nil),
                                          PollenOutlookDay(grassIndex: nil, treeIndex: nil, weedIndex: nil)])
        #expect(fetched.value.outlook?.first?.overallIndex == 3)
        #expect(fetched.attempt.requestParameters == #"{"days":5}"#)
    }

    @Test("Offline transport failures are recorded as not sent; a timeout may have reached the provider")
    func offlineIsNotSent() async throws {
        for (code, status) in [(URLError.Code.notConnectedToInternet, ProviderAttempt.Status.notSent),
                               (.cannotFindHost, .notSent), (.timedOut, .networkError)] {
            let failure = try #require(await failure {
                try await makeClient { _ in throw URLError(code) }.pollen(at: coordinate)
            })
            #expect(failure.attempt.status == status, "\(code)")
        }
    }

    @Test("Empty pollen data is unavailable, not a measured zero")
    func emptyPollen() async throws {
        let failure = try #require(await failure { try await makeClient { _ in (#"{"dailyInfo":[]}"#, 200) }.pollen(at: coordinate) })
        #expect(failure.attempt.status == .missingData)
        #expect(failure.underlying as? AirQualityServiceError == .missingData)
    }

    @Test("Out-of-range pollen values are rejected as unreadable")
    func outOfRangePollen() async throws {
        let body = #"{"dailyInfo":[{"pollenTypeInfo":[{"code":"GRASS","indexInfo":{"value":9}}]}]}"#
        let failure = try #require(await failure { try await makeClient { _ in (body, 200) }.pollen(at: coordinate) })
        #expect(failure.attempt.status == .decodeError)
    }

    @Test("HTTP failure keeps its status and body without decoding it as a reading")
    func serverFailure() async throws {
        let failure = try #require(await failure { try await makeClient { _ in ("unavailable", 503) }.airQuality(at: coordinate) })
        #expect(failure.attempt.status == .httpError)
        #expect(failure.attempt.httpStatus == 503)
        #expect(failure.attempt.rawResponse == Data("unavailable".utf8))
        #expect(failure.underlying as? AirQualityServiceError == .httpStatus(503))
    }

    @Test("Malformed JSON is recorded as a decode error")
    func malformed() async throws {
        let failure = try #require(await failure { try await makeClient { _ in ("{", 200) }.airQuality(at: coordinate) })
        #expect(failure.attempt.status == .decodeError)
    }

    @Test("Missing credentials fail before contacting the provider")
    func missingCredentials() async throws {
        let client = HTTPAirQualityClient(waqiToken: "", pollenAPIKey: "", bundleIdentifier: nil,
                                          transport: FixtureTransport { _ in
            Issue.record("Network must not be contacted without credentials")
            return ("", 200)
        })
        let failure = try #require(await failure { try await client.airQuality(at: coordinate) })
        #expect(failure.attempt.status == .missingCredentials)
        #expect(failure.attempt.status.rawValue == "missingCredentials")
    }

    @Test("Network failures and cancellation are recorded distinctly")
    func transportFailures() async throws {
        let offline = try #require(await failure {
            try await makeClient { _ in throw URLError(.networkConnectionLost) }.airQuality(at: coordinate)
        })
        #expect(offline.attempt.status == .networkError && !offline.isCancellation)
        let cancelled = try #require(await failure {
            try await makeClient { _ in throw CancellationError() }.pollen(at: coordinate)
        })
        #expect(cancelled.attempt.status == .cancelled && cancelled.isCancellation)
    }

    @Test("A provider's own error message becomes the recorded failure reason")
    func providerErrorMessage() async throws {
        let body = #"{"error":{"code":400,"message":"The specified time period is not supported.","status":"INVALID_ARGUMENT"}}"#
        let google = try #require(await failure {
            try await makeClient { _ in (body, 400) }.airQualityHistory(at: coordinate, hours: 1, pageToken: nil, pageIndex: 0)
        })
        #expect(google.attempt.failureDetail == "HTTP 400: The specified time period is not supported.")
        #expect(google.errorDescription == "The air quality provider rejected the request (HTTP 400).")
        let waqi = try #require(await failure {
            try await makeClient { _ in (#"{"status":"error","data":"Unknown station"}"#, 200) }.airQuality(at: coordinate)
        })
        #expect(waqi.attempt.failureDetail == "Unknown station")
    }

    @Test("History requests POST the last-N-hours form and page token, with the key only in the URL")
    func history() async throws {
        let body = #"{"hoursInfo":[{"dateTime":"2026-09-14T13:00:00Z","indexes":[{"code":"uaqi","aqi":80,"category":"Excellent air quality","dominantPollutant":"o3"}],"pollutants":[{"code":"pm25","concentration":{"value":4.1,"units":"MICROGRAMS_PER_CUBIC_METER"}}]},{"dateTime":"2026-09-14T14:00:00Z"}],"nextPageToken":"next"}"#
        let client = makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://airquality.googleapis.com/v1/history:lookup?key=test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "test.app")
            let httpBody = try #require(request.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
            let location = try #require(json["location"] as? [String: Double])
            #expect(json["hours"] as? Int == 29)
            #expect(json["period"] == nil)
            #expect(location == ["latitude": 40.12, "longitude": -74.99])
            #expect(json["pageSize"] as? Int == 168)
            #expect(json["pageToken"] as? String == "abc")
            return (body, 200)
        }
        let fetched = try await client.airQualityHistory(at: coordinate, hours: 29, pageToken: "abc", pageIndex: 1)

        let first = AirQualityHour(
            hourStart: try Date("2026-09-14T13:00:00Z", strategy: .iso8601),
            indexes: [AirQualityIndexValue(code: "uaqi", aqi: 80, category: "Excellent air quality", dominantPollutant: "o3")],
            pollutants: [PollutantValue(code: "pm25", value: 4.1, units: "MICROGRAMS_PER_CUBIC_METER")])
        let second = AirQualityHour(hourStart: try Date("2026-09-14T14:00:00Z", strategy: .iso8601), indexes: [], pollutants: [])
        #expect(fetched.value == AirQualityHistoryPage(hours: [first, second], nextPageToken: "next"))
        #expect(fetched.attempt.parsed == .hourly([first, second]))
        #expect(fetched.attempt.pageIndex == 1)
        #expect(fetched.attempt.requestKind == "history")
        #expect(fetched.attempt.requestParameters?.contains("test-key") == false)
    }

    @Test("History keeps every readable hour: an hour with a bad or missing time is skipped, not fatal to the page")
    func historySkipsUnreadableHours() async throws {
        let body = #"{"hoursInfo":[{"dateTime":"2026-09-14T13:00:00Z","indexes":[{"code":"usa_epa","aqi":null}]},{"dateTime":"yesterday"},{"indexes":[]},"junk",{"dateTime":"2026-09-14T15:00:00Z","indexes":[{"code":"usa_epa","aqi":42}]}]}"#
        let fetched = try await makeClient { _ in (body, 200) }.airQualityHistory(at: coordinate, hours: 3, pageToken: nil, pageIndex: 0)
        #expect(fetched.value.hours.map(\.hourStart) == [try Date("2026-09-14T13:00:00Z", strategy: .iso8601),
                                                          try Date("2026-09-14T15:00:00Z", strategy: .iso8601)])
        #expect(fetched.value.hours.first?.indexes.first?.aqi == nil)  // unavailable stays nil, never 0
        #expect(fetched.value.hours.last?.indexes.first?.aqi == 42)
        #expect(fetched.value.nextPageToken == nil)
    }

    @Test("Pollen: a plant with no code, or a malformed later day, costs only itself")
    func pollenSkipsMalformedEntries() async throws {
        let body = #"{"dailyInfo":[{"date":{"year":2026,"month":9,"day":14},"pollenTypeInfo":[{"displayName":"?"},{"code":"GRASS","indexInfo":{"value":2}}],"plantInfo":[{"indexInfo":{"value":3}},{"code":"OAK","indexInfo":{"value":3}}]},"junk",{"date":{"year":2026,"month":9,"day":16},"pollenTypeInfo":[{"code":"TREE","indexInfo":{"value":5}}]}]}"#
        let fetched = try await makeClient { _ in (body, 200) }.pollen(at: coordinate)
        #expect(fetched.value.grassIndex == 2)
        #expect((fetched.value.plants ?? []).map(\.code) == ["OAK"])
        // The malformed day 2 keeps its slot, so day 3's tree value is not shifted onto day 2.
        #expect((fetched.value.outlook ?? []).map(\.treeIndex) == [nil, 5])
    }

    @Test("An empty history response is an empty page, not an error")
    func historyEmpty() async throws {
        let fetched = try await makeClient { _ in ("{}", 200) }.airQualityHistory(at: coordinate, hours: 3, pageToken: nil, pageIndex: 0)
        #expect(fetched.value == AirQualityHistoryPage(hours: [], nextPageToken: nil))
    }

    private func failure<T>(_ operation: () async throws -> T) async -> ProviderFailure? {
        do {
            _ = try await operation()
            Issue.record("Expected the request to fail")
            return nil
        } catch {
            return error as? ProviderFailure
        }
    }

    private func makeClient(_ response: @escaping @Sendable (URLRequest) throws -> (String, Int)) -> HTTPAirQualityClient {
        HTTPAirQualityClient(waqiToken: "test-token", pollenAPIKey: "test-key", bundleIdentifier: "test.app",
                             transport: FixtureTransport(response: response), clock: { fixedNow })
    }
}

private struct FixtureTransport: HTTPTransport {
    let response: @Sendable (URLRequest) throws -> (String, Int)
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (body, status) = try response(request)
        let url = try #require(request.url)
        let http = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), http)
    }
}
