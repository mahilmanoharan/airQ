import Foundation

/// App-side guard that keeps metered provider usage well inside their free tiers. It is a second
/// layer only: Cloud Console quotas are the real guarantee, since the key ships inside the app.
public protocol RequestBudgeting: Sendable {
    func permits(_ provider: EnvironmentalProvider, at date: Date) async -> Bool
}

/// Counts the app's own persisted attempts over a rolling window, so there is no separate counter
/// to drift. A 31-day window bounds every calendar month, whatever day the provider's billing
/// month starts on.
public struct RollingRequestBudget: RequestBudgeting {
    public static let window: TimeInterval = 31 * 24 * 60 * 60
    /// About 3% of Air Quality's and 20% of Pollen's free monthly usage (verified 2026-09-14:
    /// 10,000 and 5,000 free events per month respectively).
    public static let freeTierSafeLimits: [EnvironmentalProvider: Int] = [.googleAirQuality: 300, .googlePollen: 1_000]

    private let limits: [EnvironmentalProvider: Int]
    private let countSince: @Sendable (EnvironmentalProvider, Date) async throws -> Int

    public init(limits: [EnvironmentalProvider: Int] = freeTierSafeLimits,
                countSince: @escaping @Sendable (EnvironmentalProvider, Date) async throws -> Int) {
        self.limits = limits
        self.countSince = countSince
    }

    public func permits(_ provider: EnvironmentalProvider, at date: Date) async -> Bool {
        guard let limit = limits[provider] else { return true }
        do { return try await countSince(provider, date.addingTimeInterval(-Self.window)) < limit }
        catch { return false }  // Usage can't be verified, so don't spend.
    }
}
