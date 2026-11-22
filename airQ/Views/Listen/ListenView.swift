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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ListenStatusCard(model: model)
                if model.phase == .idle { listeningTools }
                if model.latest != nil { ListenSoundDetails(model: model) }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AirQStyle.background }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if model.phase == .listening {
                    Label("Microphone on", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                }
                captureAction
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .airQActionBar()
        }
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var captureAction: some View {
        let canStop = model.phase == .listening || model.phase == .stopping
        return Button {
            if canStop { stop(.userStopped) } else { start() }
        } label: {
            Label(canStop ? "Stop listening" : "Start listening", systemImage: canStop ? "stop.fill" : "mic.fill")
        }
        .buttonStyle(AirQPrimaryButtonStyle())
        .disabled(model.phase == .starting || model.phase == .stopping)
    }

    private var listeningTools: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: ListenDestination.sessions) {
                Label("Past listening sessions", systemImage: "clock")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Divider()
            Menu {
                NavigationLink("Tuning", value: ListenDestination.tuning)
                NavigationLink("Review", value: ListenDestination.review)
                NavigationLink("Classifier labels", value: ListenDestination.classifierLabels)
                Button("About listening") { disclosureStartsListening = false }
            } label: {
                Label("Listening tools", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .airQCard()
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

enum SoundLabels {
    static func display(_ label: String) -> String {
        label.replacingOccurrences(of: "_", with: " ").capitalized(with: .current)
    }
}
