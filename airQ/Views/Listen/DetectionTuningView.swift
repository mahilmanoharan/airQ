import SwiftUI
import RespiratoryKit

struct DetectionTuningView: View {
    @State private var vm: DetectionTuningViewModel

    init(store: DetectionStore) {
        _vm = State(initialValue: DetectionTuningViewModel(store: store, parameters: TuningSettings.load()))
    }

    var body: some View {
        @Bindable var vm = vm
        Form {
            Section {
                DetectionLabelPicker(label: $vm.label)
                DetectionRangePicker(range: $vm.range)
            } header: {
                Text("Data")
            } footer: {
                Text("\(vm.snapshots.count) scored windows and events from \(vm.sessions.count) sessions.")
            }

            Section {
                Slider(value: $vm.parameters.confidenceThreshold, in: 0...1)
                    .accessibilityLabel("Confidence threshold")
                    .accessibilityValue(vm.parameters.confidenceThreshold.formatted(.percent.precision(.fractionLength(0))))
            } header: {
                Text("Confidence threshold: \(vm.parameters.confidenceThreshold, format: .percent.precision(.fractionLength(0)))")
            }

            Section {
                Slider(value: $vm.parameters.minInterEventGap, in: 0...5)
                    .accessibilityLabel("Minimum gap between events")
                    .accessibilityValue("\(vm.parameters.minInterEventGap.formatted(.number.precision(.fractionLength(1)))) seconds")
            } header: {
                Text("Min inter-event gap: \(vm.parameters.minInterEventGap, format: .number.precision(.fractionLength(1)))s")
            } footer: {
                Text("Detections that follow each other within this gap are one event, since overlapping analysis windows report the same sound more than once.")
            }

            Section {
                Slider(value: $vm.parameters.boutGapThreshold, in: 1...30)
                    .accessibilityLabel("Bout gap")
                    .accessibilityValue("\(vm.parameters.boutGapThreshold.formatted(.number.precision(.fractionLength(0)))) seconds")
            } header: {
                Text("Bout gap: \(vm.parameters.boutGapThreshold, format: .number.precision(.fractionLength(0)))s")
            } footer: {
                Text("Events within this many seconds of each other are grouped into one bout. Always recomputed live — never stored.")
            }

            Section("Recomputed live") {
                LabeledContent("Above threshold", value: "\(vm.filteredEvents.count)")
                LabeledContent("After debounce", value: "\(vm.debouncedEvents.count)")
                LabeledContent("Bouts", value: "\(vm.bouts.count)")
                LabeledContent("Listening time") {
                    Text(Duration.seconds(vm.listeningDuration),
                         format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                }
            }

            Section {
                Button("Reset to defaults") { vm.parameters = DetectionTuningParameters() }
            }

            if let errorMessage = vm.errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Tuning")
        .overlay { if vm.isLoading { ProgressView() } }
        .task(id: "\(vm.label)|\(vm.range.rawValue)") { await vm.load() }
        .onChange(of: vm.parameters) { _, parameters in TuningSettings.save(parameters) }
        .refreshable { await vm.load() }
    }
}
