import SwiftUI
import AirQualityKit
import WidgetKit

@main
struct airQApp: App {
    var body: some Scene {
        WindowGroup { AppRootView() }
    }
}

private struct AppRootView: View {
    @State private var dashboard: DashboardViewModel?

    var body: some View {
        NavigationStack {
            if let dashboard {
                DashboardView(model: dashboard)
            } else {
                ProgressView("Starting airQ…")
            }
        }
        .task {
            // Start services once the view has an identity, not during repeated View init.
            if dashboard == nil {
                dashboard = DashboardViewModel(location: LocationManager(), client: makeAirQualityClient(),
                                               cache: AppGroupSnapshotCache(), didSave: {
                    WidgetCenter.shared.reloadAllTimelines()
                })
            }
        }
    }
}
