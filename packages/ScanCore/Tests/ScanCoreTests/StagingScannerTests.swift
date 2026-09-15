import Foundation
import Testing
@testable import ScanCore

struct StagingScannerTests {
    let utc = TimeZone(identifier: "UTC")!
    let start = Date(timeIntervalSince1970: 1_789_349_400) // 2026-09-14T01:30:00Z

    func writeManifest(_ manifest: BatchManifest, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ScanCoreJSON.encoder().encode(manifest).write(to: folder.appending(path: BatchManifest.fileName))
    }

    func scannerManifest(id: String, interrupted: BatchManifest.Interruption? = nil) -> BatchManifest {
        BatchManifest(id: id, source: .scanner, scanner: "Canon", settings: nil, purpose: nil, pages: 2,
                      startedAt: start, completedAt: start, interrupted: interrupted)
    }

    @Test func reportsReadyAndInterruptedBatchesAndSkipsIncompleteOnes() throws {
        let staging = try TemporaryDirectory()
        defer { staging.remove() }
        try writeManifest(scannerManifest(id: "ready"), in: staging.url.appending(path: "ready"))
        try writeManifest(scannerManifest(id: "jammed", interrupted: .init(afterPage: 1, reason: "paper jam")), in: staging.url.appending(path: "jammed"))
        try FileManager.default.createDirectory(at: staging.url.appending(path: "still-scanning"), withIntermediateDirectories: true)
        try writeManifest(scannerManifest(id: "old"), in: staging.url.appending(path: "_done/old"))
        try writeManifest(scannerManifest(id: "hidden"), in: staging.url.appending(path: ".scancore"))

        var tracker = DropTracker()
        let result = try StagingScanner(stagingRoot: staging.url).scan(now: start, tracker: &tracker)

        #expect(result.readyBatches.map(\.id) == ["ready"])
        #expect(result.interruptedBatches.map(\.id) == ["jammed"])
        #expect(result.stableDrops.isEmpty)
        #expect(result.unreadableBatchIDs.isEmpty)
    }

    @Test func reportsUnreadableManifestsWithoutHidingOtherBatches() throws {
        let staging = try TemporaryDirectory()
        defer { staging.remove() }
        try writeManifest(scannerManifest(id: "ready"), in: staging.url.appending(path: "ready"))
        let broken = staging.url.appending(path: "broken")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: broken.appending(path: BatchManifest.fileName))

        var tracker = DropTracker()
        let result = try StagingScanner(stagingRoot: staging.url).scan(now: start, tracker: &tracker)
        #expect(result.readyBatches.map(\.id) == ["ready"])
        #expect(result.unreadableBatchIDs == ["broken"])
    }

    @Test func adoptsADroppedFileOnlyAfterItsSizeIsStableForFiveSeconds() throws {
        let staging = try TemporaryDirectory()
        defer { staging.remove() }
        let drop = staging.url.appending(path: "scan.PDF")
        try Data(repeating: 1, count: 10).write(to: drop)
        try Data("ignore".utf8).write(to: staging.url.appending(path: "notes.txt"))
        let scanner = StagingScanner(stagingRoot: staging.url)
        var tracker = DropTracker()

        #expect(try scanner.scan(now: start, tracker: &tracker).stableDrops.isEmpty)
        #expect(try scanner.scan(now: start.addingTimeInterval(3), tracker: &tracker).stableDrops.isEmpty)
        try Data(repeating: 1, count: 20).write(to: drop)
        #expect(try scanner.scan(now: start.addingTimeInterval(6), tracker: &tracker).stableDrops.isEmpty)
        #expect(try scanner.scan(now: start.addingTimeInterval(10), tracker: &tracker).stableDrops.isEmpty)
        let stable = try scanner.scan(now: start.addingTimeInterval(11), tracker: &tracker).stableDrops
        #expect(stable.map(\.lastPathComponent) == ["scan.PDF"])
    }

    @Test func adoptsADroppedFileIntoATimestampedDropBatch() throws {
        let staging = try TemporaryDirectory()
        defer { staging.remove() }
        let scanner = StagingScanner(stagingRoot: staging.url)
        let first = staging.url.appending(path: "a.pdf")
        let second = staging.url.appending(path: "b.png")
        try Data("pdf".utf8).write(to: first)
        try Data("png".utf8).write(to: second)

        let batchA = try scanner.adoptDroppedFile(first, now: start, timeZone: utc)
        let batchB = try scanner.adoptDroppedFile(second, now: start, timeZone: utc)

        #expect(batchA.id == "drop-2026-09-14-013000")
        #expect(batchB.id == "drop-2026-09-14-013000-2")
        #expect(batchA.manifest.source == .drop)
        #expect(FileManager.default.fileExists(atPath: batchA.folderURL.appending(path: "a.pdf").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        var tracker = DropTracker()
        #expect(try scanner.scan(now: start, tracker: &tracker).readyBatches.map(\.id) == ["drop-2026-09-14-013000", "drop-2026-09-14-013000-2"])
    }

    @Test func recoversADropFolderWhoseManifestWasNeverWritten() throws {
        let staging = try TemporaryDirectory()
        defer { staging.remove() }
        let folder = staging.url.appending(path: "drop-2026-09-14-013000")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: folder.appending(path: "scan.pdf"))

        var tracker = DropTracker()
        let result = try StagingScanner(stagingRoot: staging.url).scan(now: start, tracker: &tracker)

        #expect(result.readyBatches.map(\.id) == ["drop-2026-09-14-013000"])
        #expect(result.readyBatches.first?.manifest.source == .drop)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: BatchManifest.fileName).path(percentEncoded: false)))
    }

    @Test func listsPageFilesInNaturalOrderAndArchivesBatches() throws {
        let staging = try TemporaryDirectory()
        defer { staging.remove() }
        let folder = staging.url.appending(path: "b1")
        try writeManifest(scannerManifest(id: "b1"), in: folder)
        for name in ["page-10.png", "page-2.png", "page-1.png"] {
            try Data("x".utf8).write(to: folder.appending(path: name))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: ".scancore"), withIntermediateDirectories: true)
        let scanner = StagingScanner(stagingRoot: staging.url)
        var tracker = DropTracker()
        let batch = try #require(try scanner.scan(now: start, tracker: &tracker).readyBatches.first)

        #expect(try scanner.pageFiles(of: batch).map(\.lastPathComponent) == ["page-1.png", "page-2.png", "page-10.png"])

        let archived = try scanner.archive(batch)
        #expect(archived.path(percentEncoded: false).hasSuffix("/_done/b1"))
        try writeManifest(scannerManifest(id: "b1"), in: folder)
        let again = try #require(try scanner.scan(now: start, tracker: &tracker).readyBatches.first)
        #expect(try scanner.archive(again).lastPathComponent == "b1-2")
    }
}
