import SwiftUI
import RespiratoryKit

struct TodayCheckInCard: View {
    @Environment(\.checkInModel) private var model
    @Environment(\.openRoute) private var openRoute
    @Namespace private var transition
    @State private var opensToday = false

    private var isLogged: Bool { model?.hasCheckedInToday == true }

    var body: some View {
        Button {
            if model?.canStartNewCheckInToday == true {
                opensToday = true
            } else {
                openRoute(.checkIn)
            }
        } label: {
            cardLabel
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("todayCheckIn")
        .matchedTransitionSource(id: "todayCheckIn", in: transition)
        .navigationDestination(isPresented: $opensToday) {
            if let model {
                CheckInFlowView(model: model, target: .today)
                    .navigationTransition(.zoom(sourceID: "todayCheckIn", in: transition))
            }
        }
        .onChange(of: opensToday) { _, isOpen in
            if !isOpen { model?.finishEditing() }
        }
        .onChange(of: AppServices.shared.eraseRevision) { opensToday = false }
    }

    private var cardLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: isLogged ? "checkmark.circle" : "heart.text.clipboard")
                .font(.title3)
                .foregroundStyle(AirQStyle.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(isLogged ? "Today’s check-in is saved" : "How was your breathing today?")
                    .font(.subheadline.weight(.semibold))
                Text(isLogged ? "View your check-in" : "Check in")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AirQStyle.accent)
            }
            Spacer(minLength: 4)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
