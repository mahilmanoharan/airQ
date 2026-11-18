import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Export view model") @MainActor
struct ExportViewModelTests {
    private func makeModel(_ folder: URL, marked: @escaping @MainActor (Date) -> Void = { _ in }) throws -> ExportViewModel {
        ExportViewModel(container: try RespiratoryStore.makeInMemoryContainer(), appVersion: "t", folder: folder,
                        didExportEverything: marked)
    }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "airq-exportvm-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("A full export is ready to share and counts as the last export; a limited one doesn't")
    func fullVersusLimited() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var marks = 0
        let model = try makeModel(folder) { _ in marks += 1 }
        await model.run(period: .last30)
        guard case .ready(let url, _) = model.phase else { Issue.record("Expected a ready export"); return }
        #expect(FileManager.default.fileExists(atPath: url.path) && marks == 0)
        await model.run(period: .everything)
        #expect(marks == 1)
    }

    @Test("Leaving removes the archive and the offer to share it; changing the period drops a finished export")
    func leaving() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try makeModel(folder)
        await model.run(period: .everything)
        guard case .ready(let first, _) = model.phase else { Issue.record("Expected a ready export"); return }
        model.periodChanged()
        if case .idle = model.phase {} else { Issue.record("A new period should clear the finished export") }
        #expect(!FileManager.default.fileExists(atPath: first.path))
        await model.run(period: .everything)
        model.leave()
        #expect(((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).isEmpty)
        if case .idle = model.phase {} else { Issue.record("Leaving should clear the ready state") }
    }

    @Test("The summary for the chosen period goes into the archive; without one the export still completes")
    func summaryIncluded() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try makeModel(folder)
        var asked: [ExportPeriod] = []
        model.summaryProvider = { period, _, _ in asked.append(period); return "summary for \(period.rawValue)" }
        await model.run(period: .last30)
        guard case .ready(_, let manifest) = model.phase else { Issue.record("Expected a ready export"); return }
        #expect(asked == [.last30])
        #expect(manifest.files.contains { $0.name == "summary.txt" })

        model.summaryProvider = { _, _, _ in nil }
        await model.run(period: .everything)
        guard case .ready(_, let plain) = model.phase else { Issue.record("Expected a ready export"); return }
        #expect(!plain.files.contains { $0.name == "summary.txt" })
    }

    @Test("Leaving or changing the period during export preparation prevents a late share offer", arguments: [false, true])
    func leavingWhilePreparing(periodChanged: Bool) async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var marks = 0
        let model = try makeModel(folder) { _ in marks += 1 }
        let summary = SuspendedExportSummary()
        model.summaryProvider = { _, _, _ in await summary.value() }
        let original = Task { await model.run(period: .everything) }
        await summary.waitUntilRequested()

        if periodChanged { model.periodChanged() } else { model.leave() }
        if case .idle = model.phase {} else { Issue.record("Leaving must reset an unfinished export") }
        summary.resume()
        await original.value

        if case .idle = model.phase {} else { Issue.record("Cancelled completion must keep the screen idle") }
        #expect(marks == 0)
        #expect(summary.wasCancelled)
        #expect(((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).isEmpty)
    }

    @Test("Erase can wait for a cancelled export worker to finish before touching the store")
    func joinsCancelledWorker() async throws {
        let model = try makeModel(tempFolder())
        let summary = SuspendedExportSummary()
        model.summaryProvider = { _, _, _ in await summary.value() }
        model.start(period: .everything)
        await summary.waitUntilRequested()

        var didJoin = false
        let wait = Task {
            await model.cancelAndWait()
            didJoin = true
        }
        while model.isExporting && !didJoin { await Task.yield() }
        #expect(!didJoin)

        summary.resume()
        await wait.value
        #expect(summary.wasCancelled)
    }

    @Test("An obsolete run cannot replace the current share offer or remove its archive",
          arguments: [false, true], [false, true])
    func obsoleteRunCannotAffectReplacement(cancelOriginal: Bool, leaveFirst: Bool) async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var marks = 0
        let model = try makeModel(folder) { _ in marks += 1 }
        let summary = SuspendedExportSummary()
        model.summaryProvider = { _, _, _ in await summary.value() }
        let original = Task { await model.run(period: .everything) }
        await summary.waitUntilRequested()
        if leaveFirst { model.leave() }
        if cancelOriginal { original.cancel() }
        model.summaryProvider = { _, _, _ in "Replacement summary" }
        await model.run(period: .last7)
        guard case .ready(let replacementURL, let replacementManifest) = model.phase else {
            summary.resume()
            await original.value
            Issue.record("Expected a ready replacement export")
            return
        }
        let replacementBytes = try Data(contentsOf: replacementURL)

        summary.resume()
        await original.value

        guard case .ready(let finalURL, let finalManifest) = model.phase else {
            Issue.record("Obsolete work must preserve the current share offer")
            return
        }
        #expect(finalURL == replacementURL)
        #expect(finalManifest.rangeStart == replacementManifest.rangeStart)
        #expect(FileManager.default.fileExists(atPath: replacementURL.path))
        if FileManager.default.fileExists(atPath: replacementURL.path) {
            #expect(try Data(contentsOf: replacementURL) == replacementBytes)
        }
        #expect(marks == 0)
    }
}

/// Suspends the real export before filesystem work, with an explicit handshake instead of timing sleeps.
@MainActor
private final class SuspendedExportSummary {
    private var continuation: CheckedContinuation<String?, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private(set) var wasCancelled = false

    func value() async -> String? {
        let result: String? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
        wasCancelled = Task.isCancelled
        return result
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func resume() {
        continuation?.resume(returning: "Obsolete summary")
        continuation = nil
    }
}
