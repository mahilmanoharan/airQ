import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public enum AirQualityServiceError: LocalizedError, Sendable, Equatable {
    case missingCredentials, invalidURL, invalidResponse, missingData
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "Air quality service credentials are not configured."
        case .invalidURL: "The air quality request could not be created."
        case .invalidResponse: "The air quality provider returned an unreadable response."
        case .missingData: "The provider has no reading for this location."
        case .httpStatus: "The air quality service is temporarily unavailable. Please try again."
        }
    }
}

/// Stateless, Sendable provider adapter. Credentials are injected by the app.
/// Request construction/decoding stays outside the app's default main-actor isolation.
public struct HTTPAirQualityClient: AirQualityFetching {
    private let waqiToken: String
    private let pollenAPIKey: String
    private let bundleIdentifier: String?
    private let transport: any HTTPTransport

    public init(waqiToken: String, pollenAPIKey: String, bundleIdentifier: String?,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.waqiToken = waqiToken
        self.pollenAPIKey = pollenAPIKey
        self.bundleIdentifier = bundleIdentifier
        self.transport = transport
    }

    public func airQuality(at coordinate: GeoCoordinate) async throws -> AirQualityReading {
        guard !waqiToken.isEmpty else { throw AirQualityServiceError.missingCredentials }
        let request = try request(
            "https://api.waqi.info/feed/geo:\(coordinate.latitude);\(coordinate.longitude)/",
            query: [URLQueryItem(name: "token", value: waqiToken)]
        )
        let response: AQResponse = try await decode(request)
        guard response.status == "ok", response.data.aqi >= 0 else { throw AirQualityServiceError.missingData }
        return AirQualityReading(aqi: response.data.aqi, dominantPollutant: response.data.dominentpol,
                                 stationName: response.data.city.name)
    }

    public func pollen(at coordinate: GeoCoordinate) async throws -> PollenReading {
        guard !pollenAPIKey.isEmpty else { throw AirQualityServiceError.missingCredentials }
        var request = try request("https://pollen.googleapis.com/v1/forecast:lookup", query: [
            URLQueryItem(name: "key", value: pollenAPIKey),
            URLQueryItem(name: "location.latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "location.longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "days", value: "1")
        ])
        if let bundleIdentifier { request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        let response: PollenResponse = try await decode(request)
        let types = response.dailyInfo?.first?.pollenTypeInfo ?? []
        let known = types.filter { ["GRASS", "TREE", "WEED"].contains($0.code) }
        guard known.contains(where: { $0.indexInfo != nil }) else { throw AirQualityServiceError.missingData }
        guard known.compactMap(\.indexInfo?.value).allSatisfy({ (0...5).contains($0) }) else {
            throw AirQualityServiceError.invalidResponse
        }
        func index(_ code: String) -> Int { known.first { $0.code == code }?.indexInfo?.value ?? 0 }
        return PollenReading(grassIndex: index("GRASS"), treeIndex: index("TREE"), weedIndex: index("WEED"))
    }

    private func request(_ url: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(string: url) else { throw AirQualityServiceError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw AirQualityServiceError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw AirQualityServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw AirQualityServiceError.httpStatus(response.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AirQualityServiceError.invalidResponse }
    }
}

private struct AQResponse: Decodable {
    struct Payload: Decodable {
        struct City: Decodable { let name: String }
        let aqi: Int
        let dominentpol: String?
        let city: City
    }
    let status: String
    let data: Payload
}

private struct PollenResponse: Decodable {
    struct Day: Decodable { let pollenTypeInfo: [PollenType]? }
    struct PollenType: Decodable {
        struct Index: Decodable { let value: Int }
        let code: String
        let indexInfo: Index?
    }
    let dailyInfo: [Day]?
}
