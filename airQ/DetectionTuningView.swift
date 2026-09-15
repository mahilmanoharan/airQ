import SwiftUI
import RespiratoryKit


struct DetectionTuningView: View {

    // MARK: - Properties

    @State private var vm: DetectionTuningViewModel

    init(store: DetectionStore) {
        _vm = State(initialValue: DetectionTuningViewModel(store: store))
    }

    // MARK: - Body

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section("Raw data") {
                LabeledContent("Stored events", value: "\(vm.snapshots.count)")
            }

            Section {
                Slider(value: $vm.parameters.confidenceThreshold, in: 0...1)
            } header: {
                Text("Confidence threshold: \(vm.parameters.confidenceThreshold, format: .percent.precision(.fractionLength(0)))")
            }

            Section {
                Slider(value: $vm.parameters.minInterEventGap, in: 0...5)
            } header: {
                Text("Min inter-event gap: \(vm.parameters.minInterEventGap, format: .number.precision(.fractionLength(1)))s")
            } footer: {
                Text("Collapses same-label detections closer together than this into one event, to account for overlapping analysis windows reporting the same physical cough.")
            }

            Section {
                Slider(value: $vm.parameters.boutGapThreshold, in: 1...30)
            } header: {
                Text("Bout gap: \(vm.parameters.boutGapThreshold, format: .number.precision(.fractionLength(0)))s")
            } footer: {
                Text("Events within this many seconds of each other are grouped into one clinical bout. Always recomputed live — never stored.")
            }

            Section("Recomputed live") {
                LabeledContent("Above threshold", value: "\(vm.filteredEvents.count)")
                LabeledContent("After debounce", value: "\(vm.debouncedEvents.count)")
                LabeledContent("Bouts", value: "\(vm.bouts.count)")
            }

            if let errorMessage = vm.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Tuning")
        .task {
            await vm.load()
        }
        .refreshable {
            await vm.load()
        }
    }
}
