import Foundation

/// A data source credited alongside the readings: WAQI's per-station attributions (the originating
/// agency and the WAQI project itself). URLs are kept only when they parse as http(s).
public struct DataAttribution: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let url: URL?
    public var id: String { name }

    public init(name: String, url: URL?) {
        self.name = name
        self.url = url.flatMap { ["http", "https"].contains($0.scheme?.lowercased()) ? $0 : nil }
    }
}
