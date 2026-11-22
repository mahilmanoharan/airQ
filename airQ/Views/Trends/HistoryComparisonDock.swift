import RespiratoryKit
import SwiftUI

struct HistoryComparisonDock: View {
    let data: ChartData
    @Binding var selection: Date?
    let inspectDay: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var selectedIndex: Int? {
        if let selection, let day = data.day(at: selection),
           let index = data.days.firstIndex(where: { $0.dayKey == day.dayKey }) {
            return index
        }
        return data.days.indices.last
    }

    var body: some View {
        if let index = selectedIndex {
            let day = data.days[index]
            HStack(spacing: 8) {
                dayButton("Previous day", symbol: "chevron.backward", index: index - 1)
                Button {
                    selection = day.interval.start
                    inspectDay()
                } label: {
                    VStack(spacing: 2) {
                        let shortDate = DayKeys.display(day.dayKey, style: .dateTime.month(.abbreviated).day())
                        if typeSize.isAccessibilitySize {
                            Image(systemName: "calendar").font(.caption)
                            Text(shortDate).font(.caption.weight(.semibold))
                        } else {
                            Text(shortDate).font(.headline)
                            Text("View day details").font(.caption.weight(.medium))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent)
                .accessibilityLabel("View day details")
                .accessibilityValue(DayKeys.display(day.dayKey, style: .dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityIdentifier("comparisonOpenDay")
                dayButton("Next day", symbol: "chevron.forward", index: index + 1)
            }
            .airQActionBar()
            .sensoryFeedback(.selection, trigger: day.dayKey)
        }
    }

    private func dayButton(_ label: String, symbol: String, index: Int) -> some View {
        Button {
            if data.days.indices.contains(index) { selection = data.days[index].interval.start }
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .disabled(!data.days.indices.contains(index))
    }
}
