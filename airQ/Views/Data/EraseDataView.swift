import SwiftUI
import SwiftData

/// Deleting everything airQ has recorded, on purpose and with friction: the person is told exactly
/// what goes, offered an export first, and must confirm. It can't be undone.
struct EraseDataView: View {
    let container: ModelContainer
    @State private var phase = Phase.idle
    @State private var isConfirming = false

    enum Phase: Equatable { case idle, erasing, done, failed(String) }

    var body: some View {
        List {
            Section {
                Label("Check-ins, life events and your review marks", systemImage: "checklist")
                Label("Listening sessions and what was heard in them", systemImage: "waveform")
                Label("Air quality and pollen history, with raw responses", systemImage: "aqi.medium")
                Label("The saved reading and place used by widgets", systemImage: "square.grid.2x2")
                Label("Listening consent, sensitivity setting and last-export time", systemImage: "slider.horizontal.3")
            } header: {
                Text("Erased")
            } footer: {
                Text("Alert and export preferences stay. Exports you already shared stay wherever you sent them; airQ can't recall them. airQ keeps only the times of its own data requests (no places or readings) so it stays within free usage limits.")
            }
            Section {
                NavigationLink(value: AppRoute.export) {
                    Label("Export a copy first", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Erasing can't be undone, and airQ has no other backup than your exports and an iPhone backup.")
            }
            Section {
                switch phase {
                case .idle, .failed:
                    Button("Erase all data…", systemImage: "trash", role: .destructive) { isConfirming = true }
                case .erasing:
                    HStack { ProgressView(); Text("Erasing…").foregroundStyle(.secondary) }
                case .done:
                    Label("Everything airQ recorded has been erased.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if case .failed(let message) = phase {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                if phase == .done {
                    Text("The next time airQ opens it also removes its database file, so nothing deleted lingers on disk, unless you have recorded something new by then. New records are never removed, so in that case erased data may remain in the file until it is reused.")
                }
            }
        }
        .navigationTitle("Erase all data")
        #if DEBUG
        .task {
            // Scratch-simulator verification of the erase + relaunch purge: `-autoErase YES`.
            if UserDefaults.standard.bool(forKey: "autoErase"), phase == .idle { await erase() }
        }
        #endif
        .confirmationDialog("Erase everything airQ has recorded?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { Task { await erase() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your check-ins, events, listening history and air quality records from this iPhone. It can't be undone.")
        }
    }

    private func erase() async {
        phase = .erasing
        do {
            try await DataEraser.eraseEverything(container: container)
            phase = .done
        } catch {
            phase = .failed("Erasing failed: \(error.localizedDescription). Nothing more was deleted; try again.")
        }
    }
}
