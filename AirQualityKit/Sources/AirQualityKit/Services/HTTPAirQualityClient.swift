import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // Provider URLs can contain coordinates and credentials. The app owns its offline cache.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public enum AirQualityServiceError: LocalizedError, Sendable, Equatable {
    case missingCredentials, invalidURL, invalidResponse, missingData
    case httpStatus(Int)
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "Air quality service credentials are not configured."
        case .invalidURL: "The air quality request could not be created."
        case .invalidResponse: "The air quality provider returned an unreadable response."
        case .missingData: "The provider has no reading for this location."
        case .httpStatus(let code) where (400..<500).contains(code):
            "The air quality provider rejected the request (HTTP \(code))."
        case .httpStatus: "The air quality service is temporarily unavailable. Please try again."
        case .transportFailed: "The air quality service could not be reached. Check your connection and try again."
        }
    }
}

/// Stateless, Sendable provider adapter. Every call returns or throws its complete request attempt
/// (verbatim body included) so the app can persist it. Coordinates are rounded before being sent.
public struct HTTPAirQualityClient: AirQualityFetching, AirQualityHistoryFetching {
    /// Bump whenever parsing changes; stored raw responses can then be re-parsed.
    public static let parserVersion = 1
    public static let historyPageSize = 168

    private let waqiToken: String
    private let googleAPIKey: String
    private let bundleIdentifier: String?
    private let transport: any HTTPTransport
    private let coordinateDecimals: Int
    private let clock: @Sendable () -> Date

    /// `pollenAPIKey` authorizes both Google Pollen and Google Air Quality requests.
    public init(waqiToken: String, pollenAPIKey: String, bundleIdentifier: String?,
                transport: any HTTPTransport = URLSessionTransport(), coordinateDecimals: Int = 2,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.waqiToken = waqiToken
        self.googleAPIKey = pollenAPIKey
        self.bundleIdentifier = bundleIdentifier
        self.transport = transport
        self.coordinateDecimals = coordinateDecimals
        self.clock = clock
    }

    public func airQuality(at coordinate: GeoCoordinate) async throws -> Fetched<AirQualityReading> {
        let sent = coordinate.rounded(toDecimals: coordinateDecimals)
        return try await execute(.waqi, kind: "current", credential: waqiToken, sent: sent,
                                 parameters: nil, pageIndex: nil, makeRequest: {
            try makeURLRequest("https://api.waqi.info/feed/geo:\(sent.latitude);\(sent.longitude)/",
                               query: [URLQueryItem(name: "token", value: waqiToken)])
        }, parse: Self.parseWAQI)
    }

    /// Google bills Pollen per successful request, not per forecast day, so the full 5-day outlook
    /// comes with the one daily request.
    static let pollenForecastDays = 5

    public func pollen(at coordinate: GeoCoordinate) async throws -> Fetched<PollenReading> {
        let sent = coordinate.rounded(toDecimals: coordinateDecimals)
        return try await execute(.googlePollen, kind: "forecast", credential: googleAPIKey, sent: sent,
                                 parameters: #"{"days":\#(Self.pollenForecastDays)}"#, pageIndex: nil, makeRequest: {
            var request = try makeURLRequest("https://pollen.googleapis.com/v1/forecast:lookup", query: [
                URLQueryItem(name: "key", value: googleAPIKey),
                URLQueryItem(name: "location.latitude", value: String(sent.latitude)),
                URLQueryItem(name: "location.longitude", value: String(sent.longitude)),
                URLQueryItem(name: "days", value: String(Self.pollenForecastDays)),
            ])
            identify(&request)
            return request
        }, parse: Self.parsePollen)
    }

    /// Uses the documented "last N hours" form: a long explicit `period` ending at the current,
    /// incomplete hour is rejected with "time period not supported".
    public func airQualityHistory(at coordinate: GeoCoordinate, hours: Int,
                                  pageToken: String?, pageIndex: Int) async throws -> Fetched<AirQualityHistoryPage> {
        let sent = coordinate.rounded(toDecimals: coordinateDecimals)
        let body = HistoryRequest(
            location: .init(latitude: sent.latitude, longitude: sent.longitude), hours: hours,
            pageSize: Self.historyPageSize, pageToken: pageToken, universalAqi: true,
            extraComputations: ["LOCAL_AQI", "POLLUTANT_CONCENTRATION"], languageCode: "en")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bodyData = try? encoder.encode(body)
        return try await execute(.googleAirQuality, kind: "history", credential: googleAPIKey, sent: sent,
                                 parameters: bodyData.map { String(decoding: $0, as: UTF8.self) },
                                 pageIndex: pageIndex, makeRequest: {
            guard let bodyData else { throw AirQualityServiceError.invalidURL }
            var request = try makeURLRequest("https://airquality.googleapis.com/v1/history:lookup",
                                             query: [URLQueryItem(name: "key", value: googleAPIKey)])
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            identify(&request)
            return request
        }, parse: Self.parseHistory)
    }

    /// Transport failures that happen before any byte reaches the provider, so they aren't usage.
    /// Others (timeouts, a dropped connection) may have reached it and are counted.
    static let neverSentCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost,
        .dnsLookupFailed, .cannotConnectToHost,
    ]

    private func execute<Value: Sendable>(
        _ provider: EnvironmentalProvider, kind: String, credential: String, sent: GeoCoordinate,
        parameters: String?, pageIndex: Int?,
        makeRequest: () throws -> URLRequest,
        parse: (Data) throws -> ParseResult<Value>
    ) async throws -> Fetched<Value> {
        var attempt = ProviderAttempt(provider: provider, requestKind: kind, requestedAt: clock(),
                                      status: .success, parserVersion: Self.parserVersion)
        attempt.coordinate = sent
        attempt.coordinateDecimals = coordinateDecimals
        attempt.requestParameters = parameters
        attempt.pageIndex = pageIndex

        func failure(_ status: ProviderAttempt.Status, _ error: any Error & Sendable,
                     detail: String? = nil) -> ProviderFailure {
            attempt.status = status
            attempt.failureDetail = detail ?? error.localizedDescription
            return ProviderFailure(attempt: attempt, underlying: error)
        }

        guard !credential.isEmpty else { throw failure(.missingCredentials, AirQualityServiceError.missingCredentials) }
        let request: URLRequest
        do { request = try makeRequest() }
        catch { throw failure(.notSent, AirQualityServiceError.invalidURL) }

        let exchange: (Data, URLResponse)
        do { exchange = try await transport.data(for: request) }
        catch is CancellationError { throw failure(.cancelled, CancellationError()) }
        catch let error as URLError {
            if error.code == .cancelled { throw failure(.cancelled, CancellationError()) }
            throw failure(Self.neverSentCodes.contains(error.code) ? .notSent : .networkError, error)
        }
        catch { throw failure(.networkError, AirQualityServiceError.transportFailed(error.localizedDescription)) }

        let (data, response) = exchange
        attempt.receivedAt = clock()
        attempt.rawResponse = data
        if Task.isCancelled { throw failure(.cancelled, CancellationError()) }
        guard let http = response as? HTTPURLResponse else {
            throw failure(.decodeError, AirQualityServiceError.invalidResponse)
        }
        attempt.httpStatus = http.statusCode
        guard (200..<300).contains(http.statusCode) else {
            throw failure(.httpError, AirQualityServiceError.httpStatus(http.statusCode),
                          detail: Self.providerMessage(in: data).map { "HTTP \(http.statusCode): \($0)" })
        }

        let result: ParseResult<Value>
        do { result = try parse(data) }
        catch { throw failure(.decodeError, AirQualityServiceError.invalidResponse) }
        switch result {
        case .reading(let value, let parsed):
            attempt.parsed = parsed
            return Fetched(value: value, attempt: attempt)
        case .noReading(let parsed, let reason):
            attempt.parsed = parsed
            throw failure(reason == .invalidResponse ? .decodeError : .missingData, reason,
                          detail: Self.providerMessage(in: data))
        }
    }

    private func makeURLRequest(_ url: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(string: url) else { throw AirQualityServiceError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw AirQualityServiceError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func identify(_ request: inout URLRequest) {
        if let bundleIdentifier { request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
    }
}
