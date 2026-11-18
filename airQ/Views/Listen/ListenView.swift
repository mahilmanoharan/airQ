import SwiftUI
import RespiratoryKit

enum ListenDestination: Hashable {
    case sessions, tuning, review, classifierLabels
}

struct ListenView: View {
    @State private var model: ListenViewModel
    @State private var wantsListening = false
    /// Nil when hidden; `true` when shown from Start (acknowledging starts listening), `false`
    /// when opened just to read it.
    @State private var disclosureStartsListening: Bool?
    @AppStorage(MicrophoneDisclosure.acknowledgedVersionKey) private var acknowledgedVersion = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.selectedTab) private var selectedTab
    private let store: DetectionStore

    init(store: DetectionStore) {
        self.store = store
        _model = State(initialValue: ListenViewModel(controller: AudioAnalysisController(), store: store,
                                                   appVersion: AppVersion.current))
    }

    var body: some View {
        VStack(spacing: 16) {
            if model.phase == .listening || model.phase == .stopping {
                MicrophoneOnHeader(startedAt: model.sessionStartedAt, windowCount: model.windowCount,
                                   isStopping: model.phase == .stopping) { stop(.userStopped) }
            } else {
                Button("Start listening", systemImage: "mic.fill") { start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.phase != .idle)
            }
            if model.phase == .idle {
                NavigationLink(value: ListenDestination.sessions) {
                    Label("Past listening sessions", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if model.phase == .starting { ProgressView("Starting microphone…") }
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if let outcome = model.lastOutcome, model.phase == .idle, outcome.failure == nil {
                Text("Saved \(outcome.windowCount) sound checks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let latest = model.latest {
                LiveWindowCard(window: latest, coughScore: model.score("cough", in: latest))
            }
            LiveWindowList(windows: model.windows, isListening: model.phase == .listening)
        }
        .padding()
        .navigationTitle("Listen")
        .navigationDestination(for: ListenDestination.self) { destination in
            switch destination {
            case .sessions: ListeningSessionsView(store: store)
            case .tuning: DetectionTuningView(store: store)
            case .review: DetectionReviewView(store: store)
            case .classifierLabels: ClassifierProbeView()
            }
        }
        .task(id: wantsListening) {
            guard wantsListening, selectedTab == .listen else { return }
            await AppServices.shared.run(.listening) { await model.listen() }
            wantsListening = false
        }
        .onAppear {
            #if DEBUG
            // Simulator verification without UI automation: `-autoStartListening YES`.
            if UserDefaults.standard.bool(forKey: "autoStartListening"), selectedTab == .listen, model.phase == .idle {
                wantsListening = true
            }
            #endif
        }
        // The tab can keep this view alive after selection changes.
        .onChange(of: selectedTab) { _, tab in
            guard tab != .listen else { return }
            disclosureStartsListening = nil
            stop(.navigatedAway)
        }
        .onDisappear { stop(.navigatedAway) }
        .onChange(of: scenePhase) { _, phase in
            // Background night listening is a separate, not-yet-implemented feature.
            if phase == .background { stop(.backgrounded) }
        }
        .sheet(isPresented: Binding(get: { disclosureStartsListening != nil },
                                    set: { if !$0 { disclosureStartsListening = nil } })) {
            let startsListening = disclosureStartsListening == true
            MicrophoneDisclosureSheet(acknowledgeTitle: startsListening ? "Start listening" : "Done") {
                acknowledgedVersion = MicrophoneDisclosure.version
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: MicrophoneDisclosure.acknowledgedAtKey)
                disclosureStartsListening = nil
                if startsListening && selectedTab == .listen { wantsListening = true }
            }
        }
        .toolbar {
            Menu {
                NavigationLink("Tuning", value: ListenDestination.tuning)
                NavigationLink("Review", value: ListenDestination.review)
                NavigationLink("Sessions", value: ListenDestination.sessions)
                NavigationLink("Classifier labels", value: ListenDestination.classifierLabels)
                Button("About listening") { disclosureStartsListening = false }
            } label: {
                Label("Detection tools", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func start() {
        if acknowledgedVersion < MicrophoneDisclosure.version {
            disclosureStartsListening = true
        } else {
            wantsListening = true
        }
    }

    private func stop(_ reason: ListeningEndReason) {
        guard wantsListening else { return }
        model.requestStop(reason)
        wantsListening = false
    }
}

/// Pinned while the microphone is on, so it's never ambiguous whether audio is being analysed.
private struct MicrophoneOnHeader: View {
    let startedAt: Date?
    let windowCount: Int
    let isStopping: Bool
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.white)
                .padding(8)
                .background(.red, in: Circle())
                .symbolEffect(.pulse, isActive: !isStopping)
            VStack(alignment: .leading, spacing: 2) {
                Text(isStopping ? "Saving…" : "Microphone on").fontWeight(.semibold)
                HStack(spacing: 4) {
                    if let startedAt {
                        Text(startedAt, style: .timer).monospacedDigit()
                        Text("·")
                    }
                    Text("^[\(windowCount) sound check](inflect: true)")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop", role: .destructive, action: stop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isStopping)
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

private struct LiveWindowCard: View {
    let window: WindowObservation
    let coughScore: Float?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Top sound").foregroundStyle(.secondary)
                Text(window.topLabel.map(SoundLabels.display) ?? "—").fontWeight(.medium)
                Spacer()
                Text(window.topScore.map { Double($0) } ?? 0, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            GridRow {
                Text("Cough").foregroundStyle(.secondary)
                ProgressView(value: Double(coughScore ?? 0)).gridCellColumns(2)
                Text(Double(coughScore ?? 0), format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
            GridRow {
                Text("Level").foregroundStyle(.secondary)
                ProgressView(value: LevelFormat.meterFraction(window.rms)).gridCellColumns(2).tint(.gray)
                Text(LevelFormat.dbfs(window.rms)).monospacedDigit()
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct LiveWindowList: View {
    let windows: [WindowObservation]
    let isListening: Bool

    var body: some View {
        if windows.isEmpty {
            ContentUnavailableView(isListening ? "Listening…" : "Not listening", systemImage: "waveform",
                                   description: Text("Keep this screen open and airQ will notice coughs and sneezes near your iPhone. Sounds are analysed on this iPhone and never recorded."))
        } else {
            List(windows) { window in
                HStack {
                    Text(window.topLabel.map(SoundLabels.display) ?? "—")
                        .fontWeight(RespiratoryLabels.allowlist.contains(window.topLabel ?? "") ? .semibold : .regular)
                    Spacer()
                    Text(window.deliveredAt, format: .dateTime.hour().minute().second())
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Double(window.topScore ?? 0), format: .percent.precision(.fractionLength(0)))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .listStyle(.plain)
        }
    }
}

enum SoundLabels {
    static func display(_ label: String) -> String {
        label.replacingOccurrences(of: "_", with: " ").capitalized(with: .current)
    }
}

enum LevelFormat {
    /// dBFS of a linear RMS amplitude.
    static func dbfs(_ rms: Float?) -> String {
        guard let rms, rms > 0 else { return "—" }
        return "\(Int((20 * log10(Double(rms))).rounded())) dB"
    }

    /// Maps -80…0 dBFS onto 0…1 for a meter.
    static func meterFraction(_ rms: Float?) -> Double {
        guard let rms, rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(Double(rms)) + 80) / 80))
    }
}
