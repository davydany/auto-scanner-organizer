import CoreGraphics
import Foundation
import Testing
@testable import ScanCore

struct BatchArtifactsTests {
    let document = DocumentAnalysis(pages: [1, 2], splitConfidence: 0.9, docType: .receipt, title: "Receipt", from: "Staples",
                                    docDate: CalendarDay("2026-09-02"), summary: "S.", keyFacts: KeyFacts(amount: Decimal(string: "84.17"), currency: "USD"))

    @Test func roundTripsEveryArtifactInTheHiddenFolder() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let artifacts = BatchArtifacts(batchFolder: temp.url)
        let pages = [PageText(page: PageRef(fileName: "page-001.png", pageIndex: 0),
                              lines: [RecognizedLine(text: "Staples", confidence: 1, boundingBox: CGRect(x: 0.125, y: 0.5, width: 0.25, height: 0.125))])]
        let stack = StoredStack(documents: [document], boundaryDocumentIndices: [0], failure: nil)
        let placed = StoredPlacement.placed(placement: Placement(folder: "Personal/Finances", newSubfolder: "2026", confidence: 0.8, reason: "r",
                                                                 ledgerNoteName: "2026 Business Receipts"), fromPurposeMapping: true)
        let ledger = LedgerFiling(noteName: "2026 Business Receipts", folder: "Personal/Finances", title: "2026 Business Receipts",
                                  purpose: "2026 taxes", taxYear: 2026, from: "Staples", amount: Decimal(string: "84.17") ?? 0, currency: "USD",
                                  category: .officeSupplies)
        let filing = StoredFiling(baseName: "2026-09-02 Staples - Receipt", folder: "Personal/Finances", docDate: try #require(CalendarDay("2026-09-02")),
                                  ledger: ledger, ledgerUpdated: false, createdFolder: true)

        try artifacts.saveOCR(pages)
        try artifacts.saveStack(stack)
        try artifacts.savePlacement(placed, documentID: "doc-1")
        try artifacts.savePlacement(.refused(category: "cyber"), documentID: "doc-2")
        try artifacts.saveFiling(filing, documentID: "doc-1")

        #expect(try artifacts.loadOCR() == pages)
        #expect(try artifacts.loadStack() == stack)
        #expect(try artifacts.loadPlacement(documentID: "doc-1") == placed)
        #expect(try artifacts.loadPlacement(documentID: "doc-2") == .refused(category: "cyber"))
        #expect(try artifacts.loadFiling(documentID: "doc-1") == filing)
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.url.appending(path: ".scancore").path(percentEncoded: false)).sorted()
        #expect(names == ["filing-doc-1.json", "ocr.json", "placement-doc-1.json", "placement-doc-2.json", "stack.json"])
    }

    @Test func filingsSavedBeforeCreatedFolderExistedStillLoad() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let artifacts = BatchArtifacts(batchFolder: temp.url)
        let filing = StoredFiling(baseName: "2026-09-02 Staples - Receipt", folder: "Personal/Finances", docDate: try #require(CalendarDay("2026-09-02")),
                                  ledger: nil, ledgerUpdated: true, createdFolder: true)
        var object = try #require(try JSONSerialization.jsonObject(with: ScanCoreJSON.encoder().encode(filing)) as? [String: Any])
        #expect(object.removeValue(forKey: "created_folder") as? Bool == true)
        try FileManager.default.createDirectory(at: artifacts.folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: artifacts.folder.appending(path: "filing-doc-1.json"))

        var legacy = filing
        legacy.createdFolder = false
        #expect(try artifacts.loadFiling(documentID: "doc-1") == legacy)
    }

    @Test func missingArtifactsAreNilAndCorruptOnesThrow() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let artifacts = BatchArtifacts(batchFolder: temp.url)

        #expect(try artifacts.loadOCR() == nil)
        #expect(try artifacts.loadFiling(documentID: "doc-9") == nil)
        try FileManager.default.createDirectory(at: artifacts.folder, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: artifacts.folder.appending(path: "stack.json"))
        #expect(throws: (any Error).self) { try artifacts.loadStack() }
    }

    @Test func storedStackKeepsTheWholeBatchForReviewWhenReadingFails() {
        let refused = StoredStack(.refused(category: "cyber"), pageCount: 3)
        #expect(refused.documents.map(\.pages) == [[1, 2, 3]])
        #expect(refused.documents.first?.title == "Unreadable Scan")
        #expect(refused.failure?.reviewReason == .refused(category: "cyber"))
        #expect(StoredStack(.invalid(messages: ["a.", "b."]), pageCount: 1).failure?.reviewReason == .validationFailed(message: "a. b."))
        #expect(StoredStack(.read(documents: [document], boundaryDocumentIndices: [2, 1]), pageCount: 2).boundaryDocumentIndices == [1, 2])
    }

    @Test func storedPlacementMapsOutcomesToReviewReasons() {
        let placement = Placement(folder: "Work", confidence: 0.9, reason: "r")
        #expect(StoredPlacement(.placed(placement)) == .placed(placement: placement, fromPurposeMapping: false))
        #expect(StoredPlacement(.placed(placement)).reviewReasons.isEmpty)
        #expect(StoredPlacement(.refused(category: "bio")).reviewReasons == [.refused(category: "bio")])
        #expect(StoredPlacement(.invalid(messages: ["x.", "y."])).reviewReasons == [.validationFailed(message: "x. y.")])
        #expect(StoredPlacement(stackFailure: .invalid(messages: ["z."])) == .invalid(messages: ["z."]))
    }

    @Test func documentIDsAreStable() {
        #expect(BatchArtifacts.documentID(at: 0) == "doc-1")
        #expect(BatchArtifacts.documentIndex(of: "doc-12") == 11)
        for invalid in ["doc-0", "doc-", "x-1", "doc-1a", "../doc-1"] {
            #expect(BatchArtifacts.documentIndex(of: invalid) == nil)
        }
    }

    @Test func payloadsRecordUsageAndReasonsAndSurviveTheEventLogFormat() throws {
        let usage = PipelinePayload.usage(Usage(inputTokens: 1000, outputTokens: 100, cacheCreationInputTokens: 5, cacheReadInputTokens: 7), model: .sonnet5)
        #expect(usage == [
            JobPayloadKey.model: "claude-sonnet-5", JobPayloadKey.inputTokens: "1000", JobPayloadKey.outputTokens: "100",
            JobPayloadKey.cacheWriteTokens: "5", JobPayloadKey.cacheReadTokens: "7", JobPayloadKey.costUsd: "0.0030139",
        ])
        let reasons: [ReviewReason] = [.uncertainSplit(confidence: 0.4), .ledgerRejected(reason: "mixed currency")]
        #expect(PipelinePayload.decodeReasons(PipelinePayload.encodeReasons(reasons)) == reasons)
        #expect(PipelinePayload.decodeReasons("garbage").isEmpty)
        #expect(PipelinePayload.decodeReasons(nil).isEmpty)

        var payload = usage
        for key in [JobPayloadKey.source, JobPayloadKey.purpose, JobPayloadKey.pages, JobPayloadKey.folder, JobPayloadKey.confidence,
                    JobPayloadKey.noteName, JobPayloadKey.reasons, JobPayloadKey.documentIDs, JobPayloadKey.ledger, JobPayloadKey.step,
                    JobPayloadKey.message] {
            payload[key] = "value of \(key)"
        }
        let event = JobEvent(batchID: "b1", documentID: "doc-1", at: Date(timeIntervalSince1970: 1_789_349_400), kind: .needsReview, payload: payload)
        #expect(try ScanCoreJSON.decoder().decode(JobEvent.self, from: ScanCoreJSON.encoder().encode(event)) == event)
    }
}
