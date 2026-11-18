import AirQualityKit
import Foundation
import RespiratoryKit
import SwiftData
import UserNotifications
import WidgetKit

/// The single "erase everything" action behind `EraseDataView`. It only ever runs because the
/// person confirmed it in the app: it is the one exception to the record being append-only.
@MainActor
enum DataEraser {
    /// Everything recorded about the person: every row in the record store, the saved reading and
    /// place shared with the widgets, exports waiting in the temporary folder, the listening
    /// consent record, the last export time and the detection-tuning view. Alert and export
    /// preferences stay: they are settings, not records.
    static func eraseEverything(container: ModelContainer) async throws {
        try await AppServices.shared.eraseRecords {
            // UI tests wipe their in-memory store and cache without touching device preferences.
            guard !AppServices.isUITesting else {
                try await RespiratoryStore.eraseAll(in: container, defaultsSuite: "airq.uitest.erase")
                return
            }
            let exports = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: exports.path) {
                try FileManager.default.removeItem(at: exports)
            }
            try await RespiratoryStore.eraseAll(in: container)
            URLCache.shared.removeAllCachedResponses()  // Legacy builds used URLSession.shared.
            TuningSettings.reset()
            let defaults = UserDefaults.standard
            for key in [ExportPreferences.lastExportAtKey, MicrophoneDisclosure.acknowledgedVersionKey, MicrophoneDisclosure.acknowledgedAtKey] {
                defaults.removeObject(forKey: key)
            }
            let alertIDs = [AirQualityAlertKind.air, .pollen].map { AlertTapRouter.identifierPrefix + $0.rawValue }
            let notifications = UNUserNotificationCenter.current()
            notifications.removePendingNotificationRequests(withIdentifiers: alertIDs)
            notifications.removeDeliveredNotifications(withIdentifiers: alertIDs)
        }
        guard !AppServices.isUITesting else { return }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
