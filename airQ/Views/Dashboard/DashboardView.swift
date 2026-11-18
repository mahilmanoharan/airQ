import SwiftUI
import AirQualityKit
import RespiratoryKit

struct DashboardView: View {
    let model: DashboardViewModel
    @Environment(\.openURL) private var openURL
    /// False until the first load has finished, so "no reading yet" isn't flashed before it starts.
    @State private var hasAttemptedLoad = false

    /// Open Settings when that's the fix (location denied), otherwise a retry.
    @ViewBuilder private var errorAction: some View {
        if model.errorIsRecoverableInSettings, let settings = URL(string: UIApplication.openSettingsURLString) {
            Button("Open Settings") { openURL(settings) }
        } else {
            Button("Retry") { Task { await model.load(forceRefresh: true) } }
                .disabled(model.isLoading)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    AirQPageHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased(),
                                   title: "Your day, in context", detail: "A look at the air. A moment for you.")
                    if let message = model.errorMessage, model.snapshot != nil {
                        UpdateFailedBanner(message: message) { errorAction }
                    }
                    if let snapshot = model.snapshot {
                        DashboardEssentialsView(snapshot: snapshot)
                        // The reading above is current; only the copy widgets read is behind. The next load retries.
                        if let note = model.widgetSaveError {
                            Label(note, systemImage: "square.grid.2x2")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if model.errorMessage == nil {
                        if model.isLoading || !hasAttemptedLoad {
                            ProgressView("Loading air quality…")
                                .padding(.top, 80)
                        } else {
                            // A load that ended without a reading or an error (e.g. it was cancelled).
                            ContentUnavailableView {
                                Label("No reading yet", systemImage: "aqi.medium")
                            } description: {
                                Text("airQ couldn't load air quality just now.")
                            } actions: {
                                errorAction
                            }
                        }
                    }

                    TodayCheckInCard()

                    if let snapshot = model.snapshot {
                        DashboardMeaningView(snapshot: snapshot)
                        TomorrowCard(snapshot: snapshot)
                        DashboardDetailsSection(snapshot: snapshot)
                    }

                    if let message = model.errorMessage, model.snapshot == nil {
                        ContentUnavailableView {
                            Label("Unable to update", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            errorAction
                        }
                    }
                }
                .padding()
                // A readable column on iPad and in landscape rather than edge-to-edge cards.
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            // Simulator verification without scroll automation: `-dashboardScrollTo recentAirQuality`.
            .task(id: model.snapshot != nil) {
                guard model.snapshot != nil,
                      let anchor = UserDefaults.standard.string(forKey: "dashboardScrollTo").flatMap(DashboardAnchor.init)
                else { return }
                proxy.scrollTo(anchor, anchor: .top)
            }
            #endif
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            hasAttemptedLoad = true
        }
        .refreshable { await model.load(forceRefresh: true) }
        .toolbar {
            if model.isLoading, model.snapshot != nil { ProgressView() }
            if let snapshot = model.snapshot {
                // Plain text from the saved reading (the same sentence Siri speaks), incl. its age if old.
                ShareLink(item: AirQualitySummary.sentence(for: snapshot)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share air quality")
            }
        }
    }

    private var backgroundColor: Color {
        AirQStyle.page
    }
}

/// The details toggle, the detail sections and the data-sources footer under a reading. It reads the record
/// itself, so a newly saved attempt redraws this section rather than the whole dashboard.
private struct DashboardDetailsSection: View {
    let snapshot: AQSnapshot
    @Environment(\.recordStore) private var recordStore
    @Environment(\.environmentRecorder) private var recorder
    /// The detail sections are hidden until asked for; the choice is remembered.
    @AppStorage("dashboardShowsDetails") private var showsDetails = false

    var body: some View {
        DetailsToggle(isShown: $showsDetails)
        if showsDetails {
            DashboardDetailsView(snapshot: snapshot)
            if let recordStore, let coordinate = snapshot.coordinate {
                let place = RecordPlace(latitude: coordinate.latitude, longitude: coordinate.longitude)
                // Keep the chart's drag state across nearby GPS updates. A move beyond
                // the cache radius clears the snapshot and remounts these cards.
                VStack {
                    RecentAirQualityCard(records: recordStore, place: place, refreshKey: recorder?.revision ?? 0)
                }
                .id(DashboardAnchor.recentAirQuality)
                MonthAirQualityCard(records: recordStore, place: place, refreshKey: recorder?.revision ?? 0)
                    .id(DashboardAnchor.monthSummary)
            }
        }
        DataSourcesFooter(attributions: snapshot.attributions ?? [])
            .id(DashboardAnchor.dataSources)
    }
}

enum DashboardAnchor: String {
    case recentAirQuality, monthSummary, dataSources
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
            action().font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }
}

/// One plain control between "just tell me" and "show me everything". Its state is spoken, and it
/// remembers the choice so nobody has to reopen the detail every day.
private struct DetailsToggle: View {
    @Binding var isShown: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isShown.toggle() }
        } label: {
            HStack {
                Text(isShown ? "Hide details" : "Show details")
                    .font(.headline)
                Spacer()
                Image(systemName: isShown ? "chevron.up" : "chevron.down")
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isShown ? "Hides the pollutants, weather, forecast and charts" : "Shows the pollutants, weather, forecast and charts")
    }
}

extension View {
    /// The rounded, lightly filled panel every dashboard card sits on.
    func dashboardCard() -> some View {
        airQCard()
    }
}
