import SwiftUI
import RespiratoryKit

struct ListenView: View {
    @State private var model: ListenViewModel
    @State private var wantsListening = false
    @Environment(\.scenePhase) private var scenePhase
    private let store: DetectionStore

    init(store: DetectionStore) {
        self.store = store
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        _model = State(initialValue: ListenViewModel(controller: AudioAnalysisController(), store: store,
                                                   appVersion: "\(version) (\(build))"))
    }

    var body: some View {
        VStack(spacing: 20) {
            Button(wantsListening ? "Stop" : "Start") { wantsListening.toggle() }
                .buttonStyle(.borderedProminent)
                .tint(wantsListening ? .red : .blue)
                .disabled(model.phase == .stopping || (!wantsListening && model.phase != .idle))
            if model.phase == .starting { ProgressView("Starting microphone…") }
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            DetectionLiveList(detections: model.detections, isListening: model.phase == .listening)
        }
        .padding()
        .navigationTitle("Listen")
        .task(id: wantsListening) {
            guard wantsListening else { return }
            await model.listen()
            wantsListening = false
        }
        .onChange(of: scenePhase) { _, phase in
            // Background night listening is a separate, not-yet-implemented feature.
            if phase == .background { wantsListening = false }
        }
        .toolbar {
            Menu {
                NavigationLink("Tuning") { DetectionTuningView(store: store) }
                NavigationLink("Review") { DetectionReviewView(store: store) }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Detection tools")
        }
    }
}

private struct DetectionLiveList: View {
    let detections: [RawDetection]
    let isListening: Bool

    var body: some View {
        if detections.isEmpty {
            ContentUnavailableView(isListening ? "Listening…" : "No detections yet", systemImage: "waveform")
        } else {
            List(detections) { detection in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detection.label).fontWeight(.medium)
                        Text(detection.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(detection.confidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
    }
}
