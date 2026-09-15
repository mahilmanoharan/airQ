import SwiftUI
import AirQualityKit
import RespiratoryKit
import WidgetKit

extension EnvironmentValues {
    @Entry var detectionStore: DetectionStore? = nil
    @Entry var detectionStoreError: String? = nil
}

@main
struct airQApp: App {
    var body: some Scene {
        WindowGroup { AppRootView() }
    }
}

private struct AppRootView: View {
    @State private var dashboard: DashboardViewModel?
    @State private var store: DetectionStore?
    @State private var storeError: String?

    var body: some View {
        NavigationStack {
            if let dashboard {
                DashboardView(model: dashboard)
            } else {
                ProgressView("Starting airQ…")
            }
        }
        .environment(\.detectionStore, store)
        .environment(\.detectionStoreError, storeError)
        .task {
            // Start services once the view has an identity, not during repeated View init.
            if dashboard == nil {
                dashboard = DashboardViewModel(location: LocationManager(), client: makeAirQualityClient(),
                                               cache: AppGroupSnapshotCache(), didSave: {
                    WidgetCenter.shared.reloadAllTimelines()
                })
            }
            guard store == nil else { return }
            do { store = try await DetectionStore.open() }
            catch { storeError = "Detection history could not be opened: \(error.localizedDescription)" }
        }
    }
}

struct ListenDestinationView: View {
    @Environment(\.detectionStore) private var store
    @Environment(\.detectionStoreError) private var storeError

    var body: some View {
        if let store {
            ListenView(store: store)
        } else if let storeError {
            ContentUnavailableView("History unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                   description: Text("\(storeError) Restart airQ to retry; existing history has not been deleted."))
        } else {
            ProgressView("Opening detection history…")
        }
    }
}
