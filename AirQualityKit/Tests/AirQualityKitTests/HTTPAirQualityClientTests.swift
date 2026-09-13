import Foundation
import Testing
@testable import AirQualityKit

@Suite("HTTP air quality client")
struct HTTPAirQualityClientTests {
    private let coordinate = GeoCoordinate(latitude: 40, longitude: -74)

    @Test("AQ requests encode coordinates and token and map provider data")
    func airQuality() async throws {
        let client = makeClient { request in
            #expect(request.url?.absoluteString.hasPrefix("https://api.waqi.info/feed/geo:40.0;-74.0/?") == true)
            let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(items?.contains(URLQueryItem(name: "token", value: "test-token")) == true)
            return (#"{"status":"ok","data":{"aqi":42,"dominentpol":"pm25","city":{"name":"Test"}}}"#, 200)
        }
        let value = try await client.airQuality(at: coordinate)
        #expect(value.aqi == 42)
        #expect(value.dominantPollutant == "pm25")
    }

    @Test("Pollen requests include app identity and map the highest available index")
    func pollen() async throws {
        let client = makeClient { request in
            #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "test.app")
            return (#"{"dailyInfo":[{"pollenTypeInfo":[{"code":"GRASS","indexInfo":{"value":1}},{"code":"TREE","indexInfo":{"value":4}}]}]}"#, 200)
        }
        #expect(try await client.pollen(at: coordinate).overallIndex == 4)
    }

    @Test("Empty pollen data is unavailable, not a measured zero")
    func emptyPollen() async {
        let client = makeClient { _ in (#"{"dailyInfo":[]}"#, 200) }
        await #expect(throws: AirQualityServiceError.missingData) {
            try await client.pollen(at: coordinate)
        }
    }

    @Test("HTTP failure does not decode an error body as a reading")
    func serverFailure() async {
        let client = makeClient { _ in ("unavailable", 503) }
        await #expect(throws: AirQualityServiceError.httpStatus(503)) {
            try await client.airQuality(at: coordinate)
        }
    }

    @Test("Negative AQI values are rejected")
    func invalidReading() async {
        let client = makeClient { _ in (#"{"status":"ok","data":{"aqi":-1,"city":{"name":"Test"}}}"#, 200) }
        await #expect(throws: AirQualityServiceError.missingData) {
            try await client.airQuality(at: coordinate)
        }
    }

    @Test("Missing credentials fail before contacting the provider")
    func missingCredentials() async {
        let client = HTTPAirQualityClient(waqiToken: "", pollenAPIKey: "", bundleIdentifier: nil,
                                         transport: FixtureTransport { _ in
            Issue.record("Network must not be contacted without credentials")
            return ("", 200)
        })
        await #expect(throws: AirQualityServiceError.missingCredentials) {
            try await client.airQuality(at: coordinate)
        }
    }

    private func makeClient(_ response: @escaping @Sendable (URLRequest) throws -> (String, Int)) -> HTTPAirQualityClient {
        HTTPAirQualityClient(waqiToken: "test-token", pollenAPIKey: "test-key",
                             bundleIdentifier: "test.app", transport: FixtureTransport(response: response))
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
