import SwiftUI
import AirQualityKit
import RespiratoryKit

struct DashboardMetricDetailView: View {
    let metric: DashboardMetric
    let snapshot: AQSnapshot
    @State private var showsScale = false

    private var scaleTitle: String { metric == .airQuality ? "AQI scale" : "Pollen scale" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    readingSummary.id("currentReading")
                    switch metric {
                    case .airQuality:
                        AirQualityDetailContent(snapshot: snapshot)
                    case .pollen:
                        if let pollen = snapshot.pollenTypes {
                            PollenBreakdownView(pollen: pollen, fetchedAt: snapshot.pollenFetchedAt)
                        } else {
                            Text("Pollen breakdown and outlook are unavailable for this reading.")
                                .foregroundStyle(.secondary)
                                .airQCard()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            .task {
                let defaults = UserDefaults.standard
                if let anchor = defaults.string(forKey: "dashboardScrollTo") {
                    await Task.yield()
                    proxy.scrollTo(anchor, anchor: .top)
                } else if defaults.bool(forKey: "explainScale") {
                    await Task.yield()
                    showsScale = true
                }
            }
            #endif
        }
        .background { AirQStyle.background }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsScale) {
            NavigationStack {
                ScrollView {
                    ReadingScaleView(metric: metric, snapshot: snapshot)
                        .padding()
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                }
                .background { AirQStyle.background }
                .navigationTitle(scaleTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsScale = false }
                    }
                }
            }
        }
        .toolbar {
            if metric == .airQuality {
                ShareLink(item: AirQualitySummary.sentence(for: snapshot)) {
                    Label("Share air quality", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var readingSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.locationName)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let readingTime { Text(readingTime).font(.subheadline) }
            ReadingCardView(metric: metric, snapshot: snapshot, showsDetailsLink: false)
            Button { showsScale = true } label: {
                Label(metric == .airQuality ? "See AQI scale" : "See pollen scale", systemImage: "list.bullet")
                    .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
    }

    private var readingTime: String? {
        switch metric {
        case .airQuality:
            let time = snapshot.lastUpdated.formatted(date: .abbreviated, time: .shortened)
            return snapshot.isFresh(asOf: .now, within: AQSnapshot.freshFor) ? "Updated \(time)" : "Last saved \(time)"
        case .pollen:
            guard snapshot.pollenIndex != nil, let date = snapshot.pollenFetchedAt else { return nil }
            return "Forecast retrieved \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

private struct AirQualityDetailContent: View {
    let snapshot: AQSnapshot
    @Environment(\.recordStore) private var records
    @Environment(\.environmentRecorder) private var recorder

    private var place: RecordPlace? {
        snapshot.coordinate.map { RecordPlace(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        if let records, let place {
            RecentAirQualityCard(records: records, place: place, refreshKey: recorder?.revision ?? 0)
                .id("recentAirQuality")
        }
        let upcoming = AirQualityForecastDay.upcoming(snapshot.forecast ?? [], asOf: .now)
        if !upcoming.isEmpty {
            AirQualityForecastCard(days: upcoming)
        }
        if let conditions = snapshot.conditions, !conditions.isEmpty {
            StationConditionsView(conditions: conditions, dominantPollutant: snapshot.dominantPollutant)
        }
        if let pollutant = snapshot.dominantPollutant,
           snapshot.conditions?.pollutants.contains(where: { $0.code == pollutant }) != true {
            LabeledContent("Main pollutant", value: StationConditions.displayName(for: pollutant))
                .airQCard()
        }
        if let station = snapshot.station {
            StationProvenanceView(station: station, deviceCoordinate: snapshot.coordinate, fetchedAt: snapshot.lastUpdated)
        }
        if let records, let place {
            MonthAirQualityCard(records: records, place: place, refreshKey: recorder?.revision ?? 0)
                .id("monthSummary")
        }
        DataSourcesFooter(attributions: snapshot.attributions ?? [])
            .id("dataSources")
    }
}
