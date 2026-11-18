//
//  AQAccessoryViews.swift
//  airQWidget
//
//  Lock Screen (accessory) layouts. These render tinted/vibrant, so severity is
//  carried by the number, gauge fill and category text rather than by colour.
//

import SwiftUI
import WidgetKit
import AirQualityKit

/// One metric (AQI or pollen) in the shape every widget family needs.
struct WidgetMetric {
    let label: String
    let systemImage: String
    let value: Int?
    let range: ClosedRange<Double>
    let category: String
    let color: Color
    /// Tomorrow's value in words, for the medium widget.
    let footnote: String?
    /// Home Screen widgets show the metric without a value ("Unavailable") rather than the no-data view.
    let showsUnavailable: Bool
}

struct AccessoryMetricView: View {
    @Environment(\.widgetFamily) private var family
    var isStale = false
    let metric: WidgetMetric
    let locationName: String

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(inlineText, systemImage: metric.systemImage)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(metric.label, systemImage: metric.systemImage)
                        .font(.caption.weight(.semibold))
                        .widgetAccentable()
                    Text(metric.value.map(String.init) ?? "—")
                        .font(.title2.weight(.bold))
                    Text(metric.value == nil ? locationName
                         : isStale ? "\(metric.category) · old reading" : "\(metric.category) · \(locationName)")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                AccessoryCircularGauge(metric: metric)
                    .opacity(isStale ? 0.5 : 1)  // No room for text: an old reading is dimmed.
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.label)
        .accessibilityValue((metric.value.map { "\($0), \(metric.category)" } ?? "Unavailable")
                            + (isStale ? ", old reading" : ""))
    }

    private var inlineText: String {
        guard let value = metric.value else { return "\(metric.label) —" }
        return "\(metric.label) \(value) · \(isStale ? "old" : metric.category)"
    }
}

private struct AccessoryCircularGauge: View {
    let metric: WidgetMetric

    var body: some View {
        if let value = metric.value {
            Gauge(value: min(max(Double(value), metric.range.lowerBound), metric.range.upperBound),
                  in: metric.range) {
                Text(metric.label)
            } currentValueLabel: {
                Text("\(value)")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: metric.systemImage)
                    Text("—")
                }
            }
        }
    }
}

/// AQI and pollen together, for the rectangular Lock Screen slot.
struct AccessoryCombinedView: View {
    let aqi: WidgetMetric
    let pollen: WidgetMetric
    let locationName: String
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isStale ? "\(locationName) · old" : locationName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()
            row(aqi)
            row(pollen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .combine)
    }

    private func row(_ metric: WidgetMetric) -> some View {
        HStack(spacing: 4) {
            Image(systemName: metric.systemImage)
            Text(metric.value.map(String.init) ?? "—").font(.headline)
            Text(metric.value == nil ? "" : metric.category)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

struct AccessoryNoDataView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Open airQ", systemImage: "aqi.medium")
            case .accessoryRectangular:
                Label("Open airQ to load air quality", systemImage: "aqi.medium")
                    .font(.caption)
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "aqi.medium")
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}

extension AQSnapshotEntry {
    /// "Pollen", or "Pollen tomorrow" when the only forecast available is tomorrow's.
    var pollenLabel: String { pollenIsTomorrowsForecast ? "Pollen tomorrow" : "Pollen" }

    var aqiMetric: WidgetMetric {
        WidgetMetric(label: "AQI", systemImage: "aqi.medium", value: aqi, range: 0...300,
                     category: aqi.map(AirQualityPresentation.category(for:)) ?? "Unavailable",
                     color: aqi.map(AirQualityPresentation.color(for:)) ?? .gray,
                     footnote: tomorrow?.peak.map { "Tomorrow: \($0.subIndex) · \(AirQualityPresentation.category(for: $0.subIndex))" },
                     showsUnavailable: false)
    }

    var pollenMetric: WidgetMetric {
        WidgetMetric(label: pollenLabel, systemImage: "leaf", value: pollenIndex, range: 0...5,
                     category: PollenPresentation.category(for: pollenIndex),
                     color: PollenPresentation.color(for: pollenIndex),
                     footnote: pollenTomorrow.map { "Tomorrow: \($0) · \(PollenPresentation.category(for: $0))" },
                     showsUnavailable: true)
    }
}
