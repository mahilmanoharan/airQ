import Foundation
import Observation

@MainActor @Observable
public final class ContextEventsViewModel {
    public private(set) var events: [ContextEventSnapshot] = []
    public private(set) var retracted: [ContextEventSnapshot] = []
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let store: any ContextEventStoring
    private let appVersion: String
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    public init(store: any ContextEventStoring, appVersion: String, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.appVersion = appVersion
        self.timeZone = timeZone
        self.now = now
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await store.contextEventRows()
            try Task.checkCancellation()
            apply(rows)
            errorMessage = nil
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    /// Returns whether the row was saved, so a form can stay open with its input after a failure.
    @discardableResult
    public func add(_ draft: ContextEventDraft) async -> Bool {
        await append(draft, supersedes: nil, isRetraction: false)
    }

    @discardableResult
    public func revise(_ event: ContextEventSnapshot, with draft: ContextEventDraft) async -> Bool {
        await append(draft, supersedes: event.id, isRetraction: false)
    }

    @discardableResult
    public func retract(_ event: ContextEventSnapshot) async -> Bool {
        await append(event.draft, supersedes: event.id, isRetraction: true)
    }

    private func append(_ draft: ContextEventDraft, supersedes: UUID?, isRetraction: Bool) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await store.appendContextEvent(draft, supersedes: supersedes, isRetraction: isRetraction,
                                               recordedAt: now(), timeZone: timeZone, appVersion: appVersion)
            apply(try await store.contextEventRows())
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(_ rows: [ContextEventRow]) {
        let resolved = ContextEventResolution.resolve(rows)
        events = resolved.filter { !$0.isRetracted }
        retracted = resolved.filter(\.isRetracted)
    }
}
