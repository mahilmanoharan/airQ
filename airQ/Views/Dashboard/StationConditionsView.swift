import SwiftUI
import AirQualityKit

/// The station's pollutant sub-indices and weather. Sub-indices share the AQI scale, so each bar
/// is drawn against the same 0–300 range and coloured by the AQI band it falls in.
struct StationConditionsView: View {
    let conditions: StationConditions
    let dominantPollutant: String?
    @State private var explained: StationConditions.Pollutant?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !conditions.pollutants.isEmpty {
                Text("Pollutants").font(.headline)
                ForEach(conditions.pollutants) { pollutant in
                    Button { explained = pollutant } label: {
                        PollutantRow(pollutant: pollutant, isDominant: pollutant.code == dominantPollutant)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows what this pollutant is")
                }
                Text("Station sub-indices on the AQI scale, not concentrations. Tap one to learn about it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if conditions.hasWeather {
                if !conditions.pollutants.isEmpty { Divider() }
                Text("Weather at station").font(.headline)
                WeatherRow(conditions: conditions)
            }
        }
        .dashboardCard()
        .sheet(item: $explained) { PollutantInfoSheet(pollutant: $0) }
        #if DEBUG
        // Simulator verification without tap automation: `-explainPollutant pm25`.
        .task {
            guard let code = UserDefaults.standard.string(forKey: "explainPollutant") else { return }
            try? await Task.sleep(for: .seconds(1))  // Presenting mid-launch transition is dropped.
            explained = conditions.pollutants.first { $0.code == code }
        }
        #endif
    }
}

private struct PollutantRow: View {
    let pollutant: StationConditions.Pollutant
    let isDominant: Bool

    private static let scaleMaximum = 300.0

    var body: some View {
        let color = AirQualityPresentation.color(for: pollutant.subIndex)
        HStack(spacing: 12) {
            Text(pollutant.displayName)
                .font(.subheadline.weight(isDominant ? .bold : .regular))
                .frame(width: 56, alignment: .leading)
            Gauge(value: min(Double(pollutant.subIndex), Self.scaleMaximum), in: 0...Self.scaleMaximum) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(color)
            Text("\(pollutant.subIndex)")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pollutant.displayName)
        .accessibilityValue("\(pollutant.subIndex), \(AirQualityPresentation.category(for: pollutant.subIndex))"
                            + (isDominant ? ", primary pollutant" : ""))
    }
}

private struct WeatherRow: View {
    let conditions: StationConditions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { items }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { items }
        }
    }

    @ViewBuilder private var items: some View {
        if let celsius = conditions.temperatureCelsius {
            WeatherItem(systemImage: "thermometer.medium", label: "Temperature",
                        value: Measurement(value: celsius, unit: UnitTemperature.celsius)
                            .formatted(.measurement(width: .narrow, usage: .weather,
                                                    numberFormatStyle: .number.precision(.fractionLength(0)))))
        }
        if let dewPoint = conditions.dewPointCelsius {
            WeatherItem(systemImage: "drop", label: "Dew point",
                        value: Measurement(value: dewPoint, unit: UnitTemperature.celsius)
                            .formatted(.measurement(width: .narrow, usage: .weather,
                                                    numberFormatStyle: .number.precision(.fractionLength(0)))))
        }
        if let humidity = conditions.humidityPercent {
            WeatherItem(systemImage: "humidity", label: "Humidity",
                        value: (humidity / 100).formatted(.percent.precision(.fractionLength(0))))
        }
        if let wind = conditions.windMetersPerSecond {
            WeatherItem(systemImage: "wind", label: "Wind", value: Self.speed(wind),
                        detail: conditions.windGustMetersPerSecond.map { "gusts \(Self.speed($0))" })
        } else if let gust = conditions.windGustMetersPerSecond {
            WeatherItem(systemImage: "wind", label: "Wind gusts", value: Self.speed(gust), detail: "gusts")
        }
        if let pressure = conditions.pressureHectopascals {
            WeatherItem(systemImage: "gauge.with.dots.needle.50percent", label: "Pressure",
                        value: Measurement(value: pressure, unit: UnitPressure.hectopascals)
                            .formatted(.measurement(width: .abbreviated, usage: .barometric,
                                                    numberFormatStyle: .number.precision(.fractionLength(0)))))
        }
    }
}

extension WeatherRow {
    static func speed(_ metersPerSecond: Double) -> String {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

private struct WeatherItem: View {
    let systemImage: String
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(detail.map { "\(value), \($0)" } ?? value)
    }
}

#Preview {
    StationConditionsView(
        conditions: StationConditions(subIndices: ["pm25": 68, "pm10": 24, "o3": 31, "no2": 9, "t": 18.5, "h": 62, "w": 3.1, "p": 1014]),
        dominantPollutant: "pm25")
    .padding()
}
