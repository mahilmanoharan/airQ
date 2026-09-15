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
}

private actor PermissionGate {
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
