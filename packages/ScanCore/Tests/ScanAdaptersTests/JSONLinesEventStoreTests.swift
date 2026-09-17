import Foundation
import Testing
@testable import ScanAdapters
@testable import ScanCore

struct JSONLinesEventStoreTests {
    func event(_ batch: String, _ kind: JobEventKind, at seconds: TimeInterval) -> JobEvent {
        JobEvent(batchID: batch, at: Date(timeIntervalSince1970: seconds), kind: kind)
    }

    @Test func appendsEventsAndReloadsThemInANewInstance() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "data/events.jsonl")
        let first = event("a", .scanStarted, at: 1)
        let second = event("b", .scanStarted, at: 2)
        let third = event("a", .scanCompleted, at: 3)

        let store = JSONLinesEventStore(fileURL: file)
        for item in [first, second, third] {
            try await store.append(item)
        }

        let reloaded = JSONLinesEventStore(fileURL: file)
        #expect(try await reloaded.events(forBatch: "a") == [first, third])
        #expect(try await reloaded.batchIDs() == ["b", "a"])
        let text = try #require(String(data: try Data(contentsOf: file), encoding: .utf8))
        #expect(text.split(separator: "\n").count == 3)
        #expect(text.contains("\"batch_id\":\"a\""))
    }

    /// Appends an unterminated line, like a crash or a failed write mid-append.
    func appendFragment(to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"trunc".utf8))
    }

    @Test func dropsAPartialFinalLineLeftByACrashAndKeepsAppending() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "events.jsonl")
        let store = JSONLinesEventStore(fileURL: file)
        try await store.append(event("a", .scanStarted, at: 1))
        try await store.append(event("a", .scanCompleted, at: 2))
        try appendFragment(to: file)

        let recovered = JSONLinesEventStore(fileURL: file)
        #expect(try await recovered.events(forBatch: "a").count == 2)
        try await recovered.append(event("a", .ocrCompleted, at: 3))

        let reloaded = JSONLinesEventStore(fileURL: file)
        #expect(try await reloaded.events(forBatch: "a").map(\.kind) == [.scanStarted, .scanCompleted, .ocrCompleted])
    }

    @Test func readingNeverChangesTheFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "events.jsonl")
        try await JSONLinesEventStore(fileURL: file).append(event("a", .scanStarted, at: 1))
        try appendFragment(to: file)
        let size = try Data(contentsOf: file).count

        let reader = JSONLinesEventStore(fileURL: file)
        #expect(try await reader.events(forBatch: "a").map(\.kind) == [.scanStarted])
        #expect(try await reader.batchIDs() == ["a"])

        #expect(try Data(contentsOf: file).count == size)
    }

    @Test func trimsAFragmentWrittenAfterLoadingBeforeTheNextAppend() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "events.jsonl")
        let store = JSONLinesEventStore(fileURL: file)
        try await store.append(event("a", .scanStarted, at: 1))
        #expect(try await store.events(forBatch: "a").count == 1)
        try appendFragment(to: file)

        try await store.append(event("a", .scanCompleted, at: 2))

        let text = try #require(String(data: try Data(contentsOf: file), encoding: .utf8))
        #expect(!text.contains("trunc"))
        #expect(try await JSONLinesEventStore(fileURL: file).events(forBatch: "a").map(\.kind) == [.scanStarted, .scanCompleted])
    }

    @Test func throwsWhenAnEarlierLineIsCorrupt() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "events.jsonl")
        let good = try ScanCoreJSON.encoder().encode(event("a", .scanStarted, at: 1))
        var data = Data("{broken}\n".utf8)
        data.append(good)
        data.append(0x0A)
        try data.write(to: file)

        await #expect(throws: (any Error).self) { try await JSONLinesEventStore(fileURL: file).batchIDs() }
    }

    @Test func missingFileMeansNoEvents() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let store = JSONLinesEventStore(fileURL: temp.url.appending(path: "none.jsonl"))
        #expect(try await store.batchIDs().isEmpty)
    }
}
