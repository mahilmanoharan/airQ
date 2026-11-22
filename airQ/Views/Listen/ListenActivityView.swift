import RespiratoryKit
import SwiftUI

struct ListenStatusCard: View {
    let model: ListenViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isListening: Bool { model.phase == .listening }

    private var title: LocalizedStringKey {
        switch model.phase {
        case .idle: "Microphone off"
        case .starting: "Starting microphone…"
        case .listening: "Listening session"
        case .stopping: "Saving sound checks…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: isListening ? "waveform" : "mic")
                .font(.title.weight(.medium))
                .foregroundStyle(AirQStyle.accent)
                .padding(12)
                .background(.background.opacity(0.65), in: Circle())
                .symbolEffect(.pulse, isActive: isListening && !reduceMotion)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            status
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { AirQStyle.tintedSurface(isListening ? .teal : AirQStyle.accent) }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .idle:
            if let outcome = model.lastOutcome, outcome.failure == nil {
                Text("Saved ^[\(outcome.windowCount) sound check](inflect: true).")
            } else {
                Text("Check for sounds like coughs and sneezes. Results stay on this iPhone. No audio is saved.")
            }
        case .starting, .stopping:
            ProgressView()
                .accessibilityHidden(true)
        case .listening:
            if let startedAt = model.sessionStartedAt {
                Text(startedAt, style: .timer).monospacedDigit()
            }
            Text("^[\(model.windowCount) sound check](inflect: true)")
            Text("Keep this screen open while airQ listens.")
        }
    }
}

struct ListenSoundDetails: View {
    let model: ListenViewModel

    var body: some View {
        DisclosureGroup {
            if let latest = model.latest {
                LiveWindowCard(window: latest, coughScore: model.score("cough", in: latest))
            }
            LazyVStack(spacing: 0) {
                ForEach(model.windows) { window in
                    LabeledContent(window.topLabel.map(SoundLabels.display) ?? "—") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(window.deliveredAt, format: .dateTime.hour().minute().second())
                            if let score = window.topScore {
                                Text(Double(score), format: .percent.precision(.fractionLength(0)))
                            }
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        } label: {
            Label("Sound details", systemImage: "waveform")
                .frame(minHeight: 44)
        }
        .airQCard()
    }
}

private struct LiveWindowCard: View {
    let window: WindowObservation
    let coughScore: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Top sound", value: window.topLabel.map(SoundLabels.display) ?? "—")
            if let coughScore {
                LabeledContent("Cough score") {
                    Text(Double(coughScore), format: .percent.precision(.fractionLength(0)))
                }
            }
            LabeledContent("Sound level", value: level)
        }
        .font(.callout)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var level: String {
        guard let rms = window.rms, rms > 0 else { return "—" }
        return "\(Int((20 * log10(Double(rms))).rounded())) dB"
    }
}
