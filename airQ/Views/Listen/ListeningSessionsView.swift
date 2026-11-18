import SwiftUI
import RespiratoryKit

/// Every listening session in a range: the exposure denominator behind any detection count.
struct ListeningSessionsView: View {
    let store: DetectionStore
    var historyInterval: DateInterval? = nil
    @State private var range: DetectionRange = .lastWeek
    @State private var sessions: [ListeningSessionSnapshot] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if historyInterval == nil { DetectionRangePicker(range: $range) }
                LabeledContent("Listening time") {
                    Text(Duration.seconds(sessions.reduce(0) { $0 + $1.knownDuration }),
                         format: .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
                }
            } footer: {
                Text("Sessions that never closed (for example if airQ was quit) count up to their last saved window.")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section("Sessions") {
                ForEach(sessions.reversed()) { session in
                    NavigationLink { SessionDetailView(store: store, session: session) } label: { SessionRow(session: session) }
                }
            }
        }
        .overlay {
            if sessions.isEmpty && errorMessage == nil {
                ContentUnavailableView("No sessions", systemImage: "mic.slash")
            }
        }
        .navigationTitle("Sessions")
        .task(id: range) {
            do {
                let snapshots = try await store.sessions(in: historyInterval ?? range.interval(endingAt: .now))
                if let historyInterval {
                    sessions = snapshots.filter { $0.startedAt >= historyInterval.start || $0.knownEnd > historyInterval.start }
                } else {
                    sessions = snapshots
                }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SessionRow: View {
    let session: ListeningSessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startedAt, format: .dateTime.month().day().hour().minute()).fontWeight(.medium)
                Spacer()
                Text(Duration.seconds(session.knownDuration),
                     format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        var parts = ["\(session.windowCount) windows", SessionLabels.endReason(session.endReason)]
        if session.captureSemanticsVersion < CaptureLabels.captureSemanticsVersion { parts.append("legacy capture") }
        if let port = session.inputPortType { parts.append(SessionLabels.port(port)) }
        return parts.joined(separator: " · ")
    }
}

enum SessionLabels {
    static func endReason(_ raw: String?) -> String {
        guard let raw else { return "Didn't close cleanly" }
        return switch ListeningEndReason(rawValue: raw) {
        case .userStopped: "Stopped"
        case .backgrounded: "App left"
        case .navigatedAway: "Screen closed"
        case .interrupted: "Interrupted"
        case .routeChanged: "Microphone changed"
        case .overloaded: "Overloaded"
        case .analyzerFailed: "Analyser failed"
        case .flushTimedOut: "Analysis timed out"
        case .storageFailed: "Storage failed"
        case nil: raw
        }
    }

    static func port(_ raw: String) -> String {
        switch raw {
        case "MicrophoneBuiltIn": "Built-in mic"
        case "BluetoothHFP": "Bluetooth mic"
        case "MicrophoneWired", "HeadsetMicrophone": "Wired mic"
        default: raw
        }
    }
}

struct DetectionRangePicker: View {
    @Binding var range: DetectionRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(DetectionRange.allCases) { Text(Self.title($0)).tag($0) }
        }
    }

    static func title(_ range: DetectionRange) -> String {
        switch range {
        case .lastDay: "Last 24 hours"
        case .lastWeek: "Last 7 days"
        case .lastMonth: "Last 31 days"
        case .all: "All history"
        }
    }
}
