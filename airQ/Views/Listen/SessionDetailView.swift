import SwiftUI
import Charts
import RespiratoryKit

/// One session's per-window score for a label, against the current tuning threshold. Everything
/// here is read-time interpretation of stored windows.
struct SessionDetailView: View {
    let store: DetectionStore
    let session: ListeningSessionSnapshot
    @State private var label = "cough"
    @State private var points: [DetectionSnapshot] = []
    @State private var errorMessage: String?
    private let tuning = TuningSettings.load()

    var body: some View {
        List {
            Section {
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Duration") {
                    Text(Duration.seconds(session.knownDuration), format: .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
                }
                LabeledContent("Ended", value: SessionLabels.endReason(session.endReason))
                LabeledContent("Windows", value: "\(session.windowCount)")
                if let port = session.inputPortType { LabeledContent("Input", value: SessionLabels.port(port)) }
            }
            Section {
                DetectionLabelPicker(label: $label)
                if points.isEmpty {
                    Text(errorMessage ?? "No scores for this label in this session.").foregroundStyle(.secondary)
                } else {
                    SessionScoreChart(points: DetectionAnalysis.peaks(points, maximumPoints: 400), threshold: tuning.confidenceThreshold)
                        .frame(height: 180)
                        .padding(.vertical, 8)
                    LabeledContent("Windows at or above threshold",
                                   value: "\(points.count(where: { $0.confidence >= tuning.confidenceThreshold }))")
                    LabeledContent("Events after debounce", value: "\(events)")
                }
            } header: {
                Text("Scores")
            } footer: {
                Text("Dashed line: the current tuning threshold (\(tuning.confidenceThreshold.formatted(.percent.precision(.fractionLength(0))))). Change it in Tuning.\(points.count > 400 ? " Long sessions are drawn as the highest score in each stretch of time; the counts use every window." : "")")
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: label) { await load() }
    }

    private var events: Int {
        let filtered = DetectionAnalysis.filterByThreshold(points, threshold: tuning.confidenceThreshold)
        return DetectionAnalysis.debounce(filtered, minInterEventGap: tuning.minInterEventGap).count
    }

    private func load() async {
        let interval = DateInterval(start: session.startedAt, end: max(session.knownEnd, session.startedAt).addingTimeInterval(1))
        do {
            points = try await store.candidates(label: label, in: interval).filter { $0.sessionID == session.id }
            errorMessage = nil
        } catch {
            points = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct SessionScoreChart: View {
    let points: [DetectionSnapshot]
    let threshold: Double

    var body: some View {
        Chart {
            ForEach(points) { point in
                PointMark(x: .value("Time", point.timestamp), y: .value("Score", point.confidence))
                    .symbolSize(point.confidence >= threshold ? 36 : 10)
                    .foregroundStyle(point.isFalsePositive ? .gray : point.confidence >= threshold ? .purple : .secondary)
                    .accessibilityLabel(point.timestamp.formatted(date: .omitted, time: .standard))
                    .accessibilityValue(point.confidence.formatted(.percent.precision(.fractionLength(0))))
            }
            RuleMark(y: .value("Threshold", threshold))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.purple.opacity(0.6))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { AxisGridLine(); AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent()) } }
    }
}
