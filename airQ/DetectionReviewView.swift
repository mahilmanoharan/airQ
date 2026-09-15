import SwiftUI
import RespiratoryKit


struct DetectionReviewView: View {

    // MARK: - Properties

    @State private var vm: DetectionReviewViewModel

    init(store: DetectionStore) {
        _vm = State(initialValue: DetectionReviewViewModel(store: store))
    }

    // MARK: - Body

    var body: some View {
        List(vm.snapshots) { snapshot in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.label)
                        .fontWeight(.medium)
                        .strikethrough(snapshot.isFalsePositive)
                    Text(snapshot.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: "%.0f%%", snapshot.confidence * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await vm.toggleFalsePositive(snapshot) }
                } label: {
                    Image(systemName: snapshot.isFalsePositive ? "xmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(snapshot.isFalsePositive ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
                .accessibilityLabel(snapshot.isFalsePositive ? "Restore detection" : "Mark as false positive")
            }
        }
        .overlay {
            if vm.snapshots.isEmpty && !vm.isLoading && vm.errorMessage == nil {
                ContentUnavailableView("No detections yet", systemImage: "list.bullet")
            }
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom) {
            VStack {
                if let message = vm.errorMessage { Text(message).foregroundStyle(.red) }
                Text(vm.isShowingAllHistory ? "All detection history" : "Most recent \(DetectionReviewViewModel.historyLimit) detections")
                    .foregroundStyle(.secondary)
                if vm.canLoadAllHistory {
                    Button("Load all history") { Task { await vm.load(allHistory: true) } }
                        .disabled(vm.isLoading)
                }
            }
            .font(.caption)
            .padding()
            .background(.bar)
        }
        .task {
            await vm.load()
        }
        .refreshable {
            await vm.load()
        }
    }
}
