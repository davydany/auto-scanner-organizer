import Foundation
import Synchronization
import Testing
@testable import ScanCore

final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ date: Date) {
        current = Mutex(date)
    }

    var now: Date {
        current.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

struct StagingRunnerTests {
    func runner(_ harness: PipelineHarness, claude: ScriptedClaude, clock: TestClock) -> StagingRunner {
        StagingRunner(
            configuration: PipelineConfiguration(stagingRoot: harness.staging, vaultRoot: harness.vault, model: .sonnet5, threshold: 0.75,
                                                 timeZone: PipelineHarness.utc),
            services: PipelineServices(events: harness.events, purposes: harness.purposes, pages: FakePageSource(), recognizer: FakeTextRecognizer(),
                                       claude: claude, now: { clock.now })
        )
    }

    @Test func processesReadyBatchesAndReportsInterruptedAndUnreadableOnes() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        _ = try harness.stageBatch(pages: 1)
        var jammed = try harness.stageBatch(id: "2026-09-14-020000", pages: 1).manifest
        jammed.interrupted = BatchManifest.Interruption(afterPage: 1, reason: "paper jam")
        try ScanCoreJSON.encoder().encode(jammed).write(to: harness.staging.appending(path: "2026-09-14-020000/batch.json"))
        try FileManager.default.createDirectory(at: harness.staging.appending(path: "broken"), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: harness.staging.appending(path: "broken/batch.json"))
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]))), PipelineHarness.submit("s1", submitInput())])

        let pass = try await runner(harness, claude: claude, clock: TestClock(PipelineHarness.startedAt)).runOnce()

        #expect(pass.processed.map(\.batchID) == ["2026-09-14-013000"])
        #expect(pass.processed.map(\.status) == [.filed])
        #expect(pass.interrupted == ["2026-09-14-020000"])
        #expect(pass.unreadable == ["broken"])
        #expect(pass.skippedFailed.isEmpty)
    }

    @Test func adoptsADroppedFileOnceItStopsChanging() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        try Data("png".utf8).write(to: harness.staging.appending(path: "scan-001.png"))
        let clock = TestClock(PipelineHarness.startedAt)
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]))), PipelineHarness.submit("s1", submitInput())])
        let runner = runner(harness, claude: claude, clock: clock)

        #expect(try await runner.runOnce().processed.isEmpty)
        clock.advance(by: 6)
        let pass = try await runner.runOnce()

        #expect(pass.processed.map(\.batchID) == ["drop-2026-09-14-013006"])
        #expect(pass.processed.map(\.status) == [.filed])
        #expect(try harness.vaultFiles("Personal/Finances") == ["2026-08-28 Dominion Energy - Electric Bill.md", "2026-08-28 Dominion Energy - Electric Bill.pdf"])
    }

    @Test func skipsFailedBatchesUntilTheyAreRetried() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 1)
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]))),
                                     ScriptedClaude.fail(.network("offline")), PipelineHarness.submit("s1", submitInput())])
        let runner = runner(harness, claude: claude, clock: TestClock(PipelineHarness.startedAt))

        #expect(try await runner.runOnce().processed.map(\.status) == [.failed(step: .placeDocuments, message: "network(\"offline\")")])
        let skipped = try await runner.runOnce()
        #expect(skipped.processed.isEmpty)
        #expect(skipped.skippedFailed == [batch.id])
        #expect(await claude.requests.count == 2)

        try await runner.processor.retry(batchID: batch.id)
        #expect(try await runner.runOnce().processed.map(\.status) == [.filed])
    }
}
