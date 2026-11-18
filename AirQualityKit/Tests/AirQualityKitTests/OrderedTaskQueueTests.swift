import Testing
@testable import AirQualityKit

@Suite("Ordered task queue") @MainActor
struct OrderedTaskQueueTests {
    @Test("Work runs in enqueue order even when an earlier item takes longer")
    func order() async {
        let queue = OrderedTaskQueue()
        var log: [Int] = []
        queue.enqueue { try? await Task.sleep(for: .milliseconds(40)); log.append(1) }
        queue.enqueue { log.append(2) }
        queue.enqueue { await Task.yield(); log.append(3) }
        await queue.flush()
        #expect(log == [1, 2, 3])
    }

    @Test("Flush waits for everything queued before it, and is immediate when nothing is queued")
    func flushWaits() async {
        let queue = OrderedTaskQueue()
        await queue.flush()
        var done = 0
        for _ in 0..<5 { queue.enqueue { try? await Task.sleep(for: .milliseconds(5)); done += 1 } }
        #expect(done == 0)
        await queue.flush()
        #expect(done == 5)
    }
}
