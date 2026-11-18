import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Audio controller lifecycle")
struct AudioLifecycleTests {
    @Test("Pending permission reserves the controller and stop invalidates that start")
    func pendingPermission() async throws {
        let permission = PermissionGate()
        let controller = AudioAnalysisController(requestPermission: { await permission.request() })
        let starting = Task { try await controller.start() }
        await permission.waitForRequest()
        await #expect(throws: AudioAnalysisError.sessionAlreadyActive) { try await controller.start() }
        await controller.stop()
        await permission.resolve(true)
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(await controller.isRunning == false)
    }

    @Test("A denied microphone throws the permission error and leaves the controller free to start again")
    func deniedPermission() async {
        let controller = AudioAnalysisController(requestPermission: { false })
        for _ in 0..<2 {
            // The second attempt would throw sessionAlreadyActive if the first left the controller reserved.
            await #expect(throws: AudioAnalysisError.microphonePermissionDenied) { try await controller.start() }
        }
        #expect(await controller.isRunning == false)
    }

    @Test("Every error explains itself and points to the fix where there is one")
    func errorMessages() {
        let errors: [AudioAnalysisError] = [
            .microphonePermissionDenied, .sessionAlreadyActive, .invalidInputFormat, .processingOverloaded,
            .engineStartFailed(underlying: "busy"), .analysisFailed(underlying: "model"), .inputInterrupted, .routeChanged,
            .flushTimedOut,
        ]
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        #expect(AudioAnalysisError.microphonePermissionDenied.errorDescription?.contains("Settings") == true)
        #expect(AudioAnalysisError.engineStartFailed(underlying: "busy").errorDescription?.contains("busy") == true)
    }

    @Test("Cancelling during permission never starts the engine")
    func cancelledPermission() async {
        let permission = PermissionGate()
        let controller = AudioAnalysisController(requestPermission: { await permission.request() })
        let starting = Task { try await controller.start() }
        await permission.waitForRequest()
        starting.cancel()
        await permission.resolve(true)
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(await controller.isRunning == false)
    }

    @Test("A late stop for a different session leaves a pending start alone")
    func ignoresObsoleteStop() async {
        let permission = PermissionGate()
        let controller = AudioAnalysisController(requestPermission: { await permission.request() })
        let starting = Task { try await controller.start() }
        await permission.waitForRequest()
        await controller.stop(sessionID: UUID())
        await permission.resolve(false)
        await #expect(throws: AudioAnalysisError.microphonePermissionDenied) { try await starting.value }
    }
}

actor PermissionGate {
    private var pending: CheckedContinuation<Bool, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    func request() async -> Bool {
        await withCheckedContinuation {
            pending = $0
            arrival?.resume()
            arrival = nil
        }
    }
    func waitForRequest() async {
        guard pending == nil else { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resolve(_ allowed: Bool) { pending?.resume(returning: allowed); pending = nil }
}
