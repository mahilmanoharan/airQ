import SwiftUI
import RespiratoryKit

/// Candidate detections for one label above a display threshold. Verdicts are appended as
/// annotations and never change the stored observation.
struct DetectionReviewView: View {
    @State private var vm: DetectionReviewViewModel

    init(store: DetectionStore) {
        _vm = State(initialValue: DetectionReviewViewModel(store: store, appVersion: AppVersion.current))
    }

    var body: some View {
        @Bindable var vm = vm
        List {
            Section {
                DetectionLabelPicker(label: $vm.label)
                DetectionRangePicker(range: $vm.range)
                VStack(alignment: .leading) {
                    Text("Show scores from \(vm.threshold, format: .percent.precision(.fractionLength(0)))")
                    Slider(value: $vm.threshold, in: 0.05...1, step: 0.05) { editing in
                        if !editing { Task { await vm.load() } }
                    }
                    .accessibilityLabel("Minimum score shown")
                    .accessibilityValue(vm.threshold.formatted(.percent.precision(.fractionLength(0))))
                }
            } footer: {
                Text("This threshold only filters the list; every window stays stored.")
            }
            Section {
                ForEach(vm.snapshots) { snapshot in
                    ReviewRow(snapshot: snapshot) { verdict in
                        Task { await vm.toggle(verdict, for: snapshot) }
                    }
                }
            } header: {
                Text(vm.isShowingAllMatches || !vm.canShowAllMatches
                     ? "\(vm.matchingCount) candidates"
                     : "Newest \(vm.snapshots.count) of \(vm.matchingCount)")
            } footer: {
                if vm.canShowAllMatches {
                    Button("Show all \(vm.matchingCount)") { Task { await vm.load(showAll: true) } }
                        .disabled(vm.isLoading)
                }
            }
        }
        .overlay {
            if vm.snapshots.isEmpty && !vm.isLoading && vm.errorMessage == nil {
                ContentUnavailableView("No candidates", systemImage: "list.bullet",
                                       description: Text("Nothing scored at least \(vm.threshold, format: .percent.precision(.fractionLength(0))) in this range."))
            }
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom) {
            if let message = vm.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).padding().frame(maxWidth: .infinity).background(.bar)
            }
        }
        .task(id: "\(vm.label)|\(vm.range.rawValue)") { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct ReviewRow: View {
    let snapshot: DetectionSnapshot
    let toggle: (AnnotationVerdict) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .fontWeight(.medium)
                    .strikethrough(snapshot.isFalsePositive)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VerdictButton(symbol: "checkmark.circle", label: "Confirm", tint: .green,
                          isOn: snapshot.verdict == .confirmed) { toggle(.confirmed) }
            VerdictButton(symbol: "questionmark.circle", label: "Unsure", tint: .orange,
                          isOn: snapshot.verdict == .unsure) { toggle(.unsure) }
            VerdictButton(symbol: "xmark.circle", label: "False positive", tint: .red,
                          isOn: snapshot.verdict == .falsePositive) { toggle(.falsePositive) }
        }
    }

    private var detail: String {
        var parts = [snapshot.confidence.formatted(.percent.precision(.fractionLength(0)))]
        if snapshot.rank == 1 {
            parts.append("top sound")
        } else if let top = snapshot.topLabel {
            let score = snapshot.topScore.map { " \($0.formatted(.percent.precision(.fractionLength(0))))" } ?? ""
            parts.append("\(SoundLabels.display(top))\(score) ranked first")
        }
        if snapshot.source == .legacy { parts.append("legacy") }
        return parts.joined(separator: " · ")
    }
}

private struct VerdictButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "\(symbol).fill" : symbol)
                .font(.title3)
                .foregroundStyle(isOn ? tint : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct DetectionLabelPicker: View {
    @Binding var label: String

    var body: some View {
        Picker("Sound", selection: $label) {
            Section("Respiratory") {
                ForEach(RespiratoryLabels.allowlist.sorted(), id: \.self) { Text(SoundLabels.display($0)).tag($0) }
            }
            Section("Confounders") {
                ForEach(CaptureLabels.confounders, id: \.self) { Text(SoundLabels.display($0)).tag($0) }
            }
        }
    }
}
