import SwiftUI
import AirQualityKit

struct DashboardView: View {
    let model: DashboardViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.tabOpenRevision) private var tabOpenRevision
    @Namespace private var readingTransition
    /// False until the first load has finished, so "no reading yet" isn't flashed before it starts.
    @State private var hasAttemptedLoad = false
    @State private var openedMetric: DashboardMetric?

    /// Open Settings when that's the fix (location denied), otherwise a retry.
    @ViewBuilder private var errorAction: some View {
        if model.errorIsRecoverableInSettings, let settings = URL(string: UIApplication.openSettingsURLString) {
            Button("Open Settings") { openURL(settings) }
        } else {
            Button("Try again") { Task { await model.load(forceRefresh: true) } }
                .disabled(model.isLoading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let snapshot = model.snapshot {
                    if let message = model.errorMessage {
                        UpdateFailedBanner(message: message) { errorAction }
                    }
                    DashboardEssentialsView(snapshot: snapshot, transition: readingTransition) { openedMetric = $0 }
                    if let note = model.widgetSaveError {
                        Label(note, systemImage: "square.grid.2x2")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let message = model.errorMessage {
                    ContentUnavailableView {
                        Label("Unable to update", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        errorAction
                    }
                } else if model.isLoading || !hasAttemptedLoad {
                    ProgressView("Loading air quality…")
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ContentUnavailableView {
                        Label("No reading yet", systemImage: "aqi.medium")
                    } description: {
                        Text("airQ couldn't load air quality just now.")
                    } actions: {
                        errorAction
                    }
                }
                TodayCheckInCard()
                if let snapshot = model.snapshot {
                    TomorrowCard(snapshot: snapshot)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AirQStyle.atmosphere }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedMetric) { metric in
            if let snapshot = model.snapshot {
                DashboardMetricDetailView(metric: metric, snapshot: snapshot)
                    .navigationTransition(.zoom(sourceID: metric, in: readingTransition))
            } else {
                ContentUnavailableView("No saved reading", systemImage: "aqi.medium")
                    .navigationTitle(metric.title)
            }
        }
        .onChange(of: AppServices.shared.eraseRevision) { openedMetric = nil }
        .onChange(of: tabOpenRevision) { openedMetric = nil }
        .task {
            await model.load()
            hasAttemptedLoad = true
        }
        #if DEBUG
        .task(id: model.snapshot != nil) {
            let defaults = UserDefaults.standard
            guard model.snapshot != nil,
                  defaults.string(forKey: "dashboardScrollTo") != nil || defaults.bool(forKey: "explainScale")
                    || defaults.string(forKey: "explainPollutant") != nil else { return }
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { openedMetric = .airQuality }
        }
        #endif
        .refreshable { await model.load(forceRefresh: true) }
        .toolbar {
            if model.isLoading, model.snapshot != nil { ProgressView() }
        }
    }
}

private struct UpdateFailedBanner<Action: View>: View {
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Showing your last reading", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            action().buttonStyle(.bordered).controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// The rounded, lightly filled panel every dashboard card sits on.
    func dashboardCard() -> some View {
        airQCard()
    }
}
