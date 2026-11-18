import SwiftUI
import RespiratoryKit

/// Lists the labels the built-in sound classifier reports on this device and OS, marking which
/// are respiratory (allowlisted) and which are scored in every window.
struct ClassifierProbeView: View {
    @State private var labels: [String] = []
    @State private var errorMessage: String?
    @State private var filter = ""

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                LabeledContent("Labels on this device", value: "\(labels.count)")
                LabeledContent("Scored every window", value: "\(scored.count)")
                let missing = CaptureLabels.scored.filter { !labels.contains($0) }
                if !labels.isEmpty && !missing.isEmpty {
                    LabeledContent("Expected but missing", value: missing.joined(separator: ", "))
                }
            } footer: {
                Text("\u{201C}wheeze\u{201D} and \u{201C}throat clearing\u{201D} aren't labels on this classifier.")
            }
            Section("Labels") {
                ForEach(visible, id: \.self) { label in
                    HStack {
                        Text(label).font(.body.monospaced())
                        Spacer()
                        if RespiratoryLabels.allowlist.contains(label) {
                            Text("Respiratory").font(.caption).foregroundStyle(.tint)
                        } else if scored.contains(label) {
                            Text("Confounder").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $filter)
        .navigationTitle("Classifier labels")
        .task {
            do { labels = try SoundClassifierProbe.knownClassifications().sorted() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private var scored: Set<String> { Set(CaptureLabels.scored).intersection(labels) }

    private var visible: [String] {
        filter.isEmpty ? labels : labels.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
}
