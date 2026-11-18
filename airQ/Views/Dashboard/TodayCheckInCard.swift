import SwiftUI
import RespiratoryKit

/// A passive invitation beside today's air; the form opens only when requested.
struct TodayCheckInCard: View {
    @Environment(\.checkInModel) private var model
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model?.hasCheckedInToday == true ? "checkmark.circle.fill" : "heart.text.clipboard")
                    .font(.title2).foregroundStyle(AirQStyle.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model?.hasCheckedInToday == true ? "Today is logged" : "How has your breathing been?")
                        .font(.headline)
                    Text(model?.hasCheckedInToday == true
                         ? "Your answers are in History, beside the air."
                         : "A short check-in helps you see your days together.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button(action: { openRoute(.checkIn) }) {
                HStack {
                    Text(model?.hasCheckedInToday == true ? "View today's check-in" : "Check in for today")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .frame(minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent).controlSize(.large)
            Text("Optional. Skip any question.").font(.caption).foregroundStyle(.secondary)
        }
        .airQCard()
    }
}
