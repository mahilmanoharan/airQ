import SwiftUI
import AirQualityKit

/// "What do these numbers mean?": both scales in plain words, with today's level marked so the
/// number on the dashboard has something to be compared against. Local text only.
struct ScaleExplainerSheet: View {
    let aqi: Int
    let pollenIndex: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AirQualityPresentation.bands, id: \.category) { band in
                        let isNow = AirQualityPresentation.band(for: aqi).category == band.category
                        ScaleRow(color: band.color, title: band.category, range: Self.range(band.range),
                                 detail: band.guidance, isNow: isNow)
                    }
                } header: {
                    Text("Air quality (AQI)")
                } footer: {
                    Text("The AQI runs from 0 upward. The higher the number, the more polluted the air. It comes from the nearest monitoring station.")
                }
                Section {
                    ForEach(0...5, id: \.self) { level in
                        ScaleRow(color: PollenPresentation.color(for: level), title: PollenPresentation.category(for: level),
                                 range: "\(level)", detail: PollenPresentation.guidance(for: level), isNow: pollenIndex == level)
                    }
                } header: {
                    Text("Pollen (0–5)")
                } footer: {
                    Text("Pollen is a forecast for the day, from 0 (none) to 5 (very high). It isn't measured where you are.")
                }
            }
            .navigationTitle("What the numbers mean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// "0–50", or "301 and up" for the open-ended top band.
    static func range(_ range: ClosedRange<Int>) -> String {
        range.upperBound == Int.max ? "\(range.lowerBound) and up" : "\(range.lowerBound)–\(range.upperBound)"
    }
}

private struct ScaleRow: View {
    let color: Color
    let title: String
    let range: String
    let detail: String
    let isNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 14, height: 14).accessibilityHidden(true)
                Text(title).font(.headline)
                Spacer()
                Text(range).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if isNow {
                Label("Where you are now", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(range)\(isNow ? ", where you are now" : ""). \(detail)")
    }
}
