import SwiftUI
import AirQualityKit

struct DashboardView: View {
    let model: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let snapshot = model.snapshot {
                    DashboardReadingsView(snapshot: snapshot)
                } else if model.errorMessage == nil {
                    ProgressView("Loading air quality…")
                        .padding(.top, 80)
                }

                if let message = model.errorMessage {
                    ContentUnavailableView {
                        Label("Unable to update", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await model.load(forceRefresh: true) } }
                            .disabled(model.isLoading)
                    }
                }
            }
            .padding()
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("airQ")
        .task { await model.load() }
        .refreshable { await model.load(forceRefresh: true) }
        .toolbar {
            if model.isLoading, model.snapshot != nil { ProgressView() }
        }
    }

    private var backgroundColor: Color {
        model.snapshot.map { AirQualityPresentation.color(for: $0.aqi).opacity(0.05) }
            ?? Color(.systemBackground)
    }
}
