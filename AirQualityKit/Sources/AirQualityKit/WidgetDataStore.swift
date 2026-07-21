import Foundation

/// Reads/writes the latest `AQSnapshot` to the shared App Group container so both
/// the main app and the widget extension see the same data without either side
/// owning a live network or location fetch inside the widget process.
public enum WidgetDataStore {
    public static let appGroupIdentifier = "group.com.mahilmanoharan.airQ"

    private static let snapshotKey = "AQSnapshot.latest"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    public static func save(_ snapshot: AQSnapshot) {
        guard let sharedDefaults, let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        sharedDefaults.set(data, forKey: snapshotKey)
    }

    public static func loadLatest() -> AQSnapshot? {
        guard let sharedDefaults, let data = sharedDefaults.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AQSnapshot.self, from: data)
    }
}
