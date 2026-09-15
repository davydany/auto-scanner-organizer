import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import ScanCore

actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

struct CountingRecognizer: TextRecognizer {
    let counter: CallCounter
    var base = FakeTextRecognizer()

    func recognize(_ page: PageImage) async throws -> [RecognizedLine] {
        await counter.increment()
        return try await base.recognize(page)
    }
}

/// Fails the first write of a `…Receipts.md` ledger note, like a full disk or an offline iCloud file would.
final class FailingLedgerFileSystem: FileSystem, FileAttributesReading {
    private let local = LocalFileSystem()
    private let remainingFailures = Mutex(1)

    func fileExists(at url: URL) -> Bool { local.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { local.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try local.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try local.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try local.readData(at: url) }
    func createNewFile(_ data: Data, at url: URL) throws { try local.createNewFile(data, at: url) }
    func moveItem(at source: URL, to destination: URL) throws { try local.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try local.removeItem(at: url) }
    func attributes(at url: URL) throws -> FileAttributes { try local.attributes(at: url) }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let fails = url.lastPathComponent.hasSuffix("Receipts.md") && remainingFailures.withLock { remaining in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        try local.writeAtomically(data, to: url)
    }
}

/// Loses the first append of one event kind, like a crash right after the vault writes.
actor FlakyEventStore: EventStore {
    private let base = InMemoryEventStore()
    private var failing: JobEventKind?

    init(failingOnce kind: JobEventKind) {
        failing = kind
    }

    func append(_ event: JobEvent) async throws {
        if event.kind == failing {
            failing = nil
            throw CocoaError(.fileWriteUnknown)
        }
        try await base.append(event)
    }

    func events(forBatch batchID: String) async throws -> [JobEvent] {
        try await base.events(forBatch: batchID)
    }

    func batchIDs() async throws -> [String] {
        try await base.batchIDs()
    }
}

struct BatchProcessorRecoveryTests {
    let bill = StackJSON.document(pages: [1, 2])
    let fit = #"{"fits":true,"reason":"Office purchase.","tax_year":2026,"tax_category":"business-receipt","expense_category":"office-supplies"}"#

    @Test func resumesAFailedPlacementWithoutRepeatingOCROrTheStackRead() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let counter = CallCounter()
        let first = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)),
                                    ScriptedClaude.fail(.http(status: 529, type: "overloaded_error", message: "Overloaded"))])

        let failed = try await harness.processor(claude: first, recognizer: CountingRecognizer(counter: counter)).process(batch)

        guard case .failed(let step, let message) = failed.status else {
            Issue.record("expected a failed batch, got \(failed.status)")
            return
        }
        #expect(step == .placeDocuments)
        #expect(message.contains("overloaded_error"))
        #expect(try await harness.events.events(forBatch: batch.id).last?.documentID == "doc-1")

        let second = ScriptedClaude([PipelineHarness.submit("s1", submitInput())])
        let processor = harness.processor(claude: second, recognizer: CountingRecognizer(counter: counter))
        #expect(try await processor.process(batch).status == failed.status)
        #expect(await second.requests.isEmpty)

        try await processor.retry(batchID: batch.id)
        let resumed = try await processor.process(batch)

        #expect(resumed.status == .filed)
        #expect(await second.requests.count == 1)
        #expect(await counter.count == 2)
        #expect(try await harness.kinds(batch.id).suffix(6) == [.stepFailed, .retryRequested, .placementDecided, .pdfWritten, .noteWritten, .rawArchived])
    }

    @Test func retriesAFailedOCRStep() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)

        let failed = try await harness.processor(claude: ScriptedClaude([]), recognizer: FakeTextRecognizer(failingPages: [2])).process(batch)
        guard case .failed(step: .ocr, _) = failed.status else {
            Issue.record("expected an OCR failure, got \(failed.status)")
            return
        }

        let processor = harness.processor(claude: ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())]))
        try await processor.retry(batchID: batch.id)
        #expect(try await processor.process(batch).status == .filed)
    }

    @Test func finishesOnlyTheLedgerAfterALedgerWriteFails() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let purpose = "2026 taxes, business receipts"
        let batch = try harness.stageBatch(pages: 1, purpose: purpose)
        let receipt = StackJSON.document(pages: [1], title: "Office Supplies Receipt", from: "Staples", docDate: "2026-09-02", docType: "receipt",
                                         amount: "84.17", currency: "USD", purposeFit: fit)
        let first = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(receipt)), PipelineHarness.submit("s1", submitInput(ledger: "2026 Business Receipts"))])
        let fileSystem = FailingLedgerFileSystem()

        let failed = try await harness.processor(claude: first, fileSystem: fileSystem).process(batch)

        guard case .failed(step: .placeDocuments, let message) = failed.status else {
            Issue.record("expected a ledger failure, got \(failed.status)")
            return
        }
        #expect(message.contains("ledgerWriteFailed"))
        #expect(try harness.vaultFiles("Personal/Finances") == ["2026-09-02 Staples - Office Supplies Receipt.md", "2026-09-02 Staples - Office Supplies Receipt.pdf"])
        #expect(try await harness.kinds(batch.id, document: "doc-1") == [.placementDecided, .pdfWritten, .noteWritten, .stepFailed])

        let second = ScriptedClaude([])
        let processor = harness.processor(claude: second, fileSystem: fileSystem)
        try await processor.retry(batchID: batch.id)
        let resumed = try await processor.process(batch)

        #expect(resumed.status == .filed)
        #expect(await second.requests.isEmpty)
        #expect(try harness.vaultFiles("Personal/Finances") == ["2026 Business Receipts.md", "2026-09-02 Staples - Office Supplies Receipt.md",
                                                                "2026-09-02 Staples - Office Supplies Receipt.pdf"])
        #expect(try harness.text("Personal/Finances/2026 Business Receipts.md").contains("[[2026-09-02 Staples - Office Supplies Receipt]]"))
        #expect(try await harness.purposes.mapping(for: purpose)?.ledgerNoteName == "2026 Business Receipts")
        #expect(try await harness.kinds(batch.id, document: "doc-1").suffix(1) == [.ledgerUpdated])
    }

    @Test func recordsEventsLostInACrashWithoutFilingAgain() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let events = FlakyEventStore(failingOnce: .pdfWritten)
        let first = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())])

        let failed = try await harness.processor(claude: first, events: events).process(batch)
        guard case .failed = failed.status else {
            Issue.record("expected a failed batch, got \(failed.status)")
            return
        }

        let second = ScriptedClaude([])
        let processor = harness.processor(claude: second, events: events)
        try await processor.retry(batchID: batch.id)
        let resumed = try await processor.process(batch)

        #expect(resumed.status == .filed)
        #expect(await second.requests.isEmpty)
        #expect(try harness.vaultFiles("Personal/Finances") == ["2026-08-28 Dominion Energy - Electric Bill.md", "2026-08-28 Dominion Energy - Electric Bill.pdf"])
        let kinds = try await events.events(forBatch: batch.id).map(\.kind)
        #expect(kinds.suffix(5) == [.stepFailed, .retryRequested, .pdfWritten, .noteWritten, .rawArchived])
    }

    @Test func sendsARefusedStackToReviewAsOneDocument() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 3)
        let claude = ScriptedClaude([ScriptedClaude.refusal("cyber")])

        let snapshot = try await harness.processor(claude: claude).process(batch)

        #expect(snapshot.status == .needsReview)
        #expect(snapshot.documents == ["doc-1": .needsReview])
        #expect(await claude.requests.count == 1)
        let review = try #require(try await harness.events.events(forBatch: batch.id).first { $0.kind == .needsReview })
        #expect(PipelinePayload.decodeReasons(review.payload[JobPayloadKey.reasons]) == [.refused(category: "cyber")])
    }

    @Test func sendsInvalidPlacementsToReviewWithTheirMessages() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput(folder: "Nope")),
                                     PipelineHarness.submit("s2", submitInput(folder: "Nope"))])

        _ = try await harness.processor(claude: claude).process(batch)

        let review = try #require(try await harness.events.events(forBatch: batch.id).first { $0.kind == .needsReview })
        #expect(PipelinePayload.decodeReasons(review.payload[JobPayloadKey.reasons]) == [.validationFailed(message: "folder \"Nope\" does not exist in the vault.")])
    }

    @Test func sendsDocumentsWhoseFolderDisappearedToReviewUsingStoredArtifacts() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 1)
        let artifacts = BatchArtifacts(batchFolder: batch.folderURL)
        try artifacts.saveOCR([PageText(page: PageRef(fileName: "page-001.png", pageIndex: 0),
                                        lines: [RecognizedLine(text: "Stored text", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.125))])])
        try artifacts.saveStack(StoredStack(documents: try StackResponse.parse(StackJSON.stack(StackJSON.document(pages: [1])), pages: 1...1).get(),
                                            boundaryDocumentIndices: [], failure: nil))
        try artifacts.savePlacement(.placed(placement: Placement(folder: "Gone", confidence: 0.9, reason: "r"), fromPurposeMapping: false), documentID: "doc-1")
        let counter = CallCounter()
        let claude = ScriptedClaude([])

        let snapshot = try await harness.processor(claude: claude, recognizer: CountingRecognizer(counter: counter)).process(batch)

        #expect(snapshot.documents == ["doc-1": .needsReview])
        #expect(await claude.requests.isEmpty)
        #expect(await counter.count == 0)
        #expect(try await harness.kinds(batch.id) == [.batchAdopted, .ocrCompleted, .stackRead, .placementDecided, .needsReview])
        let review = try #require(try await harness.events.events(forBatch: batch.id).last)
        #expect(PipelinePayload.decodeReasons(review.payload[JobPayloadKey.reasons]) == [.folderMissing(folder: "Gone")])
    }

    @Test func failsEmptyBatchesAtOCRAndRetriesOnlyFailedBatches() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 1)
        try FileManager.default.removeItem(at: batch.folderURL.appending(path: "page-001.png"))
        let processor = harness.processor(claude: ScriptedClaude([]))

        let snapshot = try await processor.process(batch)

        #expect(snapshot.status == .failed(step: .ocr, message: "noPages"))

        let other = try harness.stageBatch(id: "2026-09-14-020000", pages: 2)
        let filed = harness.processor(claude: ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())]))
        _ = try await filed.process(other)
        try await filed.retry(batchID: other.id)
        #expect(try await harness.kinds(other.id).contains(.retryRequested) == false)
    }

    func isFailedAtPlacement(_ snapshot: BatchSnapshot) -> Bool {
        if case .failed(step: .placeDocuments, _) = snapshot.status { return true }
        return false
    }

    func count(_ kind: JobEventKind, in events: any EventStore, batch batchID: String) async throws -> Int {
        try await events.events(forBatch: batchID).filter { $0.documentID == "doc-1" && $0.kind == kind }.count
    }

    @Test func recordsALostNoteWriteOnceOnRetry() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let events = FlakyEventStore(failingOnce: .noteWritten)
        let first = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())])
        #expect(isFailedAtPlacement(try await harness.processor(claude: first, events: events).process(batch)))

        let processor = harness.processor(claude: ScriptedClaude([]), events: events)
        try await processor.retry(batchID: batch.id)

        #expect(try await processor.process(batch).status == .filed)
        #expect(try await count(.pdfWritten, in: events, batch: batch.id) == 1)
        #expect(try await count(.noteWritten, in: events, batch: batch.id) == 1)
    }

    @Test func recordsALostFolderCreationOnceOnRetry() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let events = FlakyEventStore(failingOnce: .folderCreated)
        let first = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput(newSubfolder: "2026"))])
        #expect(isFailedAtPlacement(try await harness.processor(claude: first, events: events).process(batch)))

        let processor = harness.processor(claude: ScriptedClaude([]), events: events)
        try await processor.retry(batchID: batch.id)

        #expect(try await processor.process(batch).status == .filed)
        #expect(try await count(.folderCreated, in: events, batch: batch.id) == 1)
        #expect(try harness.vaultFiles("Personal/Finances/2026") == ["2026-08-28 Dominion Energy - Electric Bill.md",
                                                                     "2026-08-28 Dominion Energy - Electric Bill.pdf"])
    }

    @Test func recordsTheLedgerUpdateOnceWhenRememberingThePurposeFails() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let purpose = "2026 taxes, business receipts"
        let batch = try harness.stageBatch(pages: 1, purpose: purpose)
        let receipt = StackJSON.document(pages: [1], title: "Office Supplies Receipt", from: "Staples", docDate: "2026-09-02", docType: "receipt",
                                         amount: "84.17", currency: "USD", purposeFit: fit)
        let purposes = FlakyPurposeStore()
        let first = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(receipt)), PipelineHarness.submit("s1", submitInput(ledger: "2026 Business Receipts"))])
        #expect(isFailedAtPlacement(try await harness.processor(claude: first, purposes: purposes).process(batch)))

        let processor = harness.processor(claude: ScriptedClaude([]), purposes: purposes)
        try await processor.retry(batchID: batch.id)

        #expect(try await processor.process(batch).status == .filed)
        #expect(try await count(.ledgerUpdated, in: harness.events, batch: batch.id) == 1)
        #expect(try await purposes.mapping(for: purpose)?.ledgerNoteName == "2026 Business Receipts")
    }

    @Test func failsThePlacementStepWhenTheDuplicateCheckCannotReadANote() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let existing = "2026-07-28 Dominion Energy - Electric Bill.md"
        try Data("---\ntitle: Electric Bill\n---\n".utf8).write(to: harness.vault.appending(path: "Personal/Finances/\(existing)"))
        let batch = try harness.stageBatch(pages: 2)
        let fileSystem = UnreadableNotesFileSystem(folder: harness.vault.appending(path: "Personal/Finances"))
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())])

        let snapshot = try await harness.processor(claude: claude, fileSystem: fileSystem).process(batch)

        guard case .failed(step: .placeDocuments, let message) = snapshot.status else {
            Issue.record("expected a failed placement step, got \(snapshot.status)")
            return
        }
        #expect(message.contains("UnreadableNoteError"))
        #expect(snapshot.documents["doc-1"] == .failed)
        #expect(try harness.vaultFiles("Personal/Finances") == [existing])
    }
}

struct UnreadableNoteError: Error {}

/// Can't read the notes in one folder, like an iCloud note that fails to download during the duplicate check.
struct UnreadableNotesFileSystem: FileSystem, FileAttributesReading {
    let folder: URL
    private let local = LocalFileSystem()

    init(folder: URL) {
        self.folder = folder
    }

    func fileExists(at url: URL) -> Bool { local.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { local.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try local.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try local.createDirectory(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws { try local.writeAtomically(data, to: url) }
    func createNewFile(_ data: Data, at url: URL) throws { try local.createNewFile(data, at: url) }
    func moveItem(at source: URL, to destination: URL) throws { try local.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try local.removeItem(at: url) }
    func attributes(at url: URL) throws -> FileAttributes { try local.attributes(at: url) }

    func readData(at url: URL) throws -> Data {
        // A resolved existing directory already ends in "/" (see VaultPathGuard), so add one only when it's missing.
        var folderPath = folder.resolvingSymlinksInPath().path(percentEncoded: false)
        if !folderPath.hasSuffix("/") { folderPath += "/" }
        if url.pathExtension == "md", url.resolvingSymlinksInPath().path(percentEncoded: false).hasPrefix(folderPath) {
            throw UnreadableNoteError()
        }
        return try local.readData(at: url)
    }
}
