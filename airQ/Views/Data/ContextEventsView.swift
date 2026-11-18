import SwiftUI
import RespiratoryKit

/// Life events that change what the record means (medication, illness, travel, moving). Append-only:
/// editing adds a new version and removing adds a retraction; nothing is deleted.
struct ContextEventsView: View {
    @State private var model: ContextEventsViewModel
    @State private var editing: ContextEventEditor.Target?
    @State private var pendingRetraction: ContextEventSnapshot?

    init(store: any ContextEventStoring) {
        _model = State(initialValue: ContextEventsViewModel(store: store, appVersion: AppVersion.current))
    }

    var body: some View {
        List {
            if let message = model.errorMessage, editing == nil {
                Section { Text(message).foregroundStyle(.red) }
            }
            Section {
                ForEach(model.events) { event in
                    Button { editing = .revise(event) } label: { ContextEventRowView(event: event) }
                        .tint(.primary)
                        .swipeActions {
                            Button("Remove", role: .destructive) { pendingRetraction = event }
                        }
                }
            } footer: {
                if !model.events.isEmpty {
                    Text("Tap to edit. Edits and removals are kept as history in exports.")
                }
            }
            if !model.retracted.isEmpty {
                Section("Removed") {
                    ForEach(model.retracted) { ContextEventRowView(event: $0).foregroundStyle(.secondary) }
                }
            }
        }
        .overlay {
            if model.events.isEmpty && model.retracted.isEmpty && !model.isLoading {
                ContentUnavailableView {
                    Label("No context events", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Log medication changes, illness, travel or a move, so later analysis can account for them.")
                } actions: {
                    Button("Add event") { editing = .add }
                }
            }
        }
        .navigationTitle("Life events")
        .toolbar {
            Button { editing = .add } label: { Label("Add event", systemImage: "plus") }
        }
        .sheet(item: $editing) { target in
            NavigationStack { ContextEventEditor(target: target, model: model) }
        }
        .confirmationDialog("Remove this event?", isPresented: .init(
            get: { pendingRetraction != nil }, set: { if !$0 { pendingRetraction = nil } }
        ), presenting: pendingRetraction) { event in
            Button("Remove", role: .destructive) { Task { await model.retract(event) } }
        } message: { _ in
            Text("It will be hidden here but kept, marked as removed, in exported data.")
        }
        .task { await model.load() }
    }
}

private struct ContextEventRowView: View {
    let event: ContextEventSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(ContextEventLabels.title(event.draft.category), systemImage: ContextEventLabels.symbol(event.draft.category))
                    .fontWeight(.medium)
                Spacer()
                if event.revisionCount > 0 {
                    Text("Edited").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(ContextEventLabels.range(event.draft)).font(.caption).foregroundStyle(.secondary)
            if !event.draft.note.isEmpty {
                Text(event.draft.note).font(.callout).lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ContextEventEditor: View {
    enum Target: Identifiable {
        case add, revise(ContextEventSnapshot)
        var id: String {
            switch self {
            case .add: "add"
            case .revise(let event): event.id.uuidString
            }
        }
    }

    let target: Target
    let model: ContextEventsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var category: String
    @State private var note: String
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date

    init(target: Target, model: ContextEventsViewModel) {
        self.target = target
        self.model = model
        switch target {
        case .add:
            _category = State(initialValue: ContextEventCategory.illness.rawValue)
            _note = State(initialValue: "")
            _start = State(initialValue: .now)
            _hasEnd = State(initialValue: false)
            _end = State(initialValue: .now)
        case .revise(let event):
            _category = State(initialValue: event.draft.category)
            _note = State(initialValue: event.draft.note)
            _start = State(initialValue: DayKeys.date(event.draft.startDayKey) ?? .now)
            _hasEnd = State(initialValue: event.draft.endDayKey != nil)
            _end = State(initialValue: event.draft.endDayKey.flatMap(DayKeys.date) ?? .now)
        }
    }

    var body: some View {
        Form {
            Picker("Type", selection: $category) {
                ForEach(ContextEventCategory.allCases) { category in
                    Label(ContextEventLabels.title(category.rawValue), systemImage: ContextEventLabels.symbol(category.rawValue))
                        .tag(category.rawValue)
                }
                if ContextEventCategory(rawValue: category) == nil { Text(category).tag(category) }
            }
            Section {
                TextField("Details, e.g. medication name and dose", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }
            Section {
                DatePicker("Started", selection: $start, in: ...Date.now, displayedComponents: .date)
                Toggle("Has an end date", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Ended", selection: $end, in: start..., displayedComponents: .date)
                }
            } footer: {
                Text(ContextEventLabels.durationHint(category))
            }
            if let message = model.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle(isRevision ? "Edit event" : "New event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(model.isSaving)
            }
        }
    }

    private var isRevision: Bool { if case .revise = target { true } else { false } }

    private func save() async {
        let draft = ContextEventDraft(category: category, note: note, startDayKey: DayKeys.key(start),
                                      endDayKey: hasEnd ? DayKeys.key(max(end, start)) : nil)
        let saved = switch target {
        case .add: await model.add(draft)
        case .revise(let event): await model.revise(event, with: draft)
        }
        if saved { dismiss() }
    }
}

/// Local-day keys for the device's current time zone, matching `LocalDay`.
nonisolated enum DayKeys {
    static func key(_ date: Date, in timeZone: TimeZone = .current) -> String {
        LocalDay(containing: date, in: timeZone).key
    }

    /// Noon of that day, so a date picker shows the right day whatever the offset.
    static func date(_ key: String) -> Date? {
        LocalDay(key: key, in: .current).map { $0.interval.start.addingTimeInterval($0.interval.duration / 2) }
    }

    static func display(_ key: String, style: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()) -> String {
        date(key)?.formatted(style) ?? key
    }
}

enum ContextEventLabels {
    static func title(_ raw: String) -> String { ContextEventCategory(rawValue: raw)?.title ?? raw }

    static func symbol(_ raw: String) -> String {
        switch ContextEventCategory(rawValue: raw) {
        case .medicationStarted, .medicationChanged, .medicationStopped: "pills"
        case .illness: "thermometer.medium"
        case .travel: "airplane"
        case .movedHome: "house"
        case .other, nil: "note.text"
        }
    }

    static func durationHint(_ raw: String) -> String {
        ContextEventCategory(rawValue: raw)?.isOpenEndedWithoutEndDate == true
            ? "Leave the end date off while it's ongoing, then edit the event to add it."
            : "Most medication changes and moves happen on one day; leave the end date off."
    }

    static func range(_ draft: ContextEventDraft) -> String {
        guard let end = draft.endDayKey, end != draft.startDayKey else { return DayKeys.display(draft.startDayKey) }
        return "\(DayKeys.display(draft.startDayKey)) – \(DayKeys.display(end))"
    }
}

#Preview("Context events") {
    NavigationStack { ContextEventsView(store: PreviewContextStore()) }
}

private actor PreviewContextStore: ContextEventStoring {
    private var rows: [ContextEventRow] = [
        ContextEventRow(id: UUID(), draft: ContextEventDraft(category: "medicationStarted", note: "Fluticasone 50 mcg",
                                                              startDayKey: DayKeys.key(.now), endDayKey: nil),
                        recordedAt: .now, recordedTimeZoneID: "UTC", supersedesID: nil, isRetraction: false),
    ]
    func contextEventRows() -> [ContextEventRow] { rows }
    func appendContextEvent(_ draft: ContextEventDraft, supersedes: UUID?, isRetraction: Bool,
                            recordedAt: Date, timeZone: TimeZone, appVersion: String) {
        rows.append(ContextEventRow(id: UUID(), draft: draft, recordedAt: recordedAt, recordedTimeZoneID: timeZone.identifier,
                                    supersedesID: supersedes, isRetraction: isRetraction))
    }
}
