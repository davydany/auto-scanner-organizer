import Foundation
import Testing
@testable import ScanAdapters

actor ChangeCounter {
    private(set) var count = 0

    func add() {
        count += 1
    }
}

struct StagingWatcherTests {
    func eventually(within timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test func signalsAtStartAndWhenABatchManifestAppearsInsideABatchFolder() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let batch = temp.url.appending(path: "2026-09-14-013000")
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        let counter = ChangeCounter()
        let listener = Task {
            for await _ in StagingWatcher(root: temp.url, pollInterval: .seconds(3600)).changes() {
                await counter.add()
            }
        }
        defer { listener.cancel() }

        #expect(await eventually { await counter.count >= 1 })
        try await Task.sleep(for: .milliseconds(500))
        let before = await counter.count
        try Data("{}".utf8).write(to: batch.appending(path: "batch.json"))

        #expect(await eventually { await counter.count > before })
    }

    @Test func ticksPeriodicallyWithoutChanges() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let counter = ChangeCounter()
        let listener = Task {
            for await _ in StagingWatcher(root: temp.url, pollInterval: .milliseconds(50)).changes() {
                await counter.add()
            }
        }
        defer { listener.cancel() }

        #expect(await eventually { await counter.count >= 4 })
    }

    @Test func keepsOnlyTheNewestTickWhileTheConsumerIsBusy() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let interval = Duration.milliseconds(100)
        var changes = StagingWatcher(root: temp.url, pollInterval: interval).changes().makeAsyncIterator()
        _ = await changes.next()

        try await Task.sleep(for: interval * 8)
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<3 {
            _ = await changes.next()
        }

        // A backlog would hand over all three at once. Holding only the newest tick means the first is the one buffered
        // while busy, and the third arrives at least one poll interval after the second, because ticks sleep in between.
        #expect(clock.now - start >= interval)
    }
}
