import SwiftUI
import RespiratoryKit

/// The check-in tab: the last week at a glance, one clear thing to do today, and the recent answers.
/// Nothing asks or pops up: the dots (and the tab's badge) show what's still open, and a tap starts it.
struct CheckInView: View {
    let model: CheckInViewModel
    @State private var flowTarget: CheckInViewModel.Target?

    var body: some View {
        List {
            Section {
                WeekStrip(days: model.recentDays) { flowTarget = $0 }
                TodayStatus(model: model) { flowTarget = .today }
                if let yesterday = model.recentDays.first(where: { $0.target == .yesterday }),
                   !yesterday.isCheckedIn, !yesterday.isBeforeFirstUse {
                    Button("Add yesterday", systemImage: "calendar.badge.plus") { flowTarget = .yesterday }
                }
            }
            if let message = model.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
            CheckInHistorySection(history: model.history, compliance: model.compliance)
        }
        .navigationTitle("Check-in")
        .navigationDestination(item: $flowTarget) { target in
            CheckInFlowView(model: model, target: target)
        }
        // Only when the card flow is closed (not when another tab is shown over it) may reloads reset the draft.
        .onChange(of: flowTarget) { _, target in if target == nil { model.finishEditing() } }
        .task {
            await model.load()
            #if DEBUG
            // Simulator verification without taps: `-openCheckInFlow YES` opens today's cards.
            if UserDefaults.standard.bool(forKey: "openCheckInFlow"), flowTarget == nil {
                try? await Task.sleep(for: .seconds(1))  // A push mid-launch transition is dropped.
                if !Task.isCancelled { flowTarget = .today }
            }
            #endif
        }
    }
}

/// Seven days as dots: filled when checked in. Today's and yesterday's open dots can be tapped to fill them.
/// No counts or streaks: a missed day is just an empty dot, never a broken chain.
private struct WeekStrip: View {
    let days: [CheckInViewModel.RecentDay]
    let open: (CheckInViewModel.Target) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                let isToday = day.target == .today
                Button { if let target = day.target { open(target) } } label: {
                    VStack(spacing: 6) {
                        if day.isBeforeFirstUse && day.target == nil {
                            // Before airQ was used: a faint point, not an empty ring that reads as "missed".
                            Circle().fill(.quaternary).frame(width: 8, height: 8).frame(width: 34, height: 34)
                        } else {
                        ZStack {
                            Circle()
                                .fill(day.isCheckedIn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                            Circle()
                                .strokeBorder(day.isCheckedIn ? AnyShapeStyle(.clear) : AnyShapeStyle(.secondary),
                                              style: StrokeStyle(lineWidth: 2, dash: day.target == nil ? [] : [4, 3]))
                            if day.isCheckedIn || day.target != nil {
                                Image(systemName: day.isCheckedIn ? "checkmark" : "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(day.isCheckedIn ? AnyShapeStyle(AirQStyle.onAccent) : AnyShapeStyle(.secondary))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay { if isToday { Circle().stroke(.tint, lineWidth: 2).padding(-4) } }
                        }
                        Text(DayKeys.display(day.dayKey, style: .dateTime.weekday(.narrow)))
                            .font(.caption2.weight(isToday ? .bold : .regular))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(day.target == nil)
                .accessibilityIdentifier(day.target.map { "checkInDay-\($0.rawValue)" } ?? "checkInDay-\(day.dayKey)")
                .accessibilityLabel(DayKeys.display(day.dayKey, style: .dateTime.weekday(.wide).month().day()))
                .accessibilityValue(day.isCheckedIn ? "Checked in" : day.isBeforeFirstUse ? "Before you started" : "Not checked in")
                .accessibilityHint(day.target == nil ? "" : day.isCheckedIn ? "Change this day's answers" : "Check in for this day")
            }
        }
        .padding(.vertical, 6)
    }
}

/// Either the one thing to do today, or that it's done (with a way back in).
private struct TodayStatus: View {
    let model: CheckInViewModel
    let start: () -> Void

    var body: some View {
        if model.hasCheckedInToday {
            VStack(alignment: .leading, spacing: 8) {
                Label("Today is logged", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if let today = model.history.first(where: { $0.row.draft.dayKey == model.recentDays.last?.dayKey }) {
                    Text(CheckInLabels.summary(today.row.draft)).foregroundStyle(.secondary)
                }
                Button("Change today's answers", action: start)
            }
            .padding(.vertical, 4)
        } else {
            Button(action: start) {
                VStack(spacing: 4) {
                    Text("Check in for today").font(.headline)
                    Text("About 20 seconds. Skip anything you like.").font(.subheadline)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
}

private struct CheckInHistorySection: View {
    let history: [(row: CheckInRow, timing: CheckInAnalysis.Timing?)]
    let compliance: (checkedIn: Int, days: Int)?

    var body: some View {
        Section {
            if let compliance {
                LabeledContent("Days checked in", value: "\(compliance.checkedIn) of \(compliance.days)")
            }
            ForEach(history.prefix(14), id: \.row.id) { entry in
                LabeledContent {
                    Text(CheckInLabels.summary(entry.row.draft)).lineLimit(1)
                } label: {
                    Text(DayKeys.display(entry.row.draft.dayKey, style: .dateTime.weekday(.abbreviated).month().day()))
                    if case .backfilled(let days) = entry.timing {
                        Text(days == 1 ? "Entered next day" : "Entered \(days) days later")
                    }
                    // The form always records how long it took; only the Siri/Shortcuts entry doesn't.
                    if entry.row.completionSeconds == nil {
                        Text("Quick entry from Siri or Shortcuts")
                    }
                }
            }
        } header: {
            Text("Recent")
        } footer: {
            Text("Days since airQ was first used. Missed days stay missing; they're never filled in.")
        }
    }
}
