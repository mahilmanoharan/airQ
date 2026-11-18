import Foundation
import RespiratoryKit

/// Tuning parameters are a viewing preference, kept in settings and never stored with data.
enum TuningSettings {
    private static let key = "detectionTuningParameters"

    static func load() -> DetectionTuningParameters {
        guard let data = UserDefaults.standard.data(forKey: key),
              let parameters = try? JSONDecoder().decode(DetectionTuningParameters.self, from: data) else { return .init() }
        return parameters
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    static func save(_ parameters: DetectionTuningParameters) {
        UserDefaults.standard.set(try? JSONEncoder().encode(parameters), forKey: key)
    }
}
