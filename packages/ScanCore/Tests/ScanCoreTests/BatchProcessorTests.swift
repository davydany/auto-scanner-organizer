import Foundation
import Testing
@testable import ScanCore

struct BatchProcessorTests {
    let bill = StackJSON.document(pages: [1, 2])
    let billName = "2026-08-28 Dominion Energy - Electric Bill"

    @Test func filesAConfidentDocumentAndArchivesTheBatch() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())])

        let snapshot = try await harness.processor(claude: claude).process(batch)

        #expect(snapshot.status == .filed)
        #expect(snapshot.nextStep == .done)
        #expect(try harness.vaultFiles("Personal/Finances") == ["\(billName).md", "\(billName).pdf"])
        let note = try harness.text("Personal/Finances/\(billName).md")
        #expect(note.contains("Page 1 text"))
        #expect(note.contains("Page 2 text"))
        #expect(!FileManager.default.fileExists(atPath: batch.folderURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: harness.staging.appending(path: "_done/\(batch.id)/.scancore/ocr.json").path(percentEncoded: false)))
        #expect(try await harness.kinds(batch.id) == [.batchAdopted, .ocrCompleted, .stackRead, .placementDecided, .pdfWritten, .noteWritten, .rawArchived])

        let events = try await harness.events.events(forBatch: batch.id)
        let stackRead = try #require(events.first { $0.kind == .stackRead })
        #expect(stackRead.payload[JobPayloadKey.documentIDs] == "doc-1")
        #expect(stackRead.payload[JobPayloadKey.model] == "claude-sonnet-5")
        #expect(stackRead.payload[JobPayloadKey.inputTokens] == "1000")
        #expect(stackRead.payload[JobPayloadKey.costUsd] == "0.003")
        let placed = try #require(events.first { $0.kind == .placementDecided })
        #expect(placed.documentID == "doc-1")
        #expect(placed.payload[JobPayloadKey.folder] == "Personal/Finances")
        #expect(events.first { $0.kind == .noteWritten }?.payload[JobPayloadKey.noteName] == billName)

        let requests = await claude.requests
        #expect(requests.count == 2)
        #expect(requests[0].messages[0].content[1] == .image(mediaType: "image/jpeg", base64Data: Data("jpeg:page-001.png#0@2576".utf8).base64EncodedString()))
        #expect(requests[1].system?.last == PlacementPrompt.indexBlock("/ (0 notes)\nPersonal (0 notes)\nPersonal/Finances (0 notes)\nWork (0 notes)"))
    }

    @Test func sendsDocumentsThatFailARuleToReviewAndKeepsTheBatch() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 3)
        let claude = ScriptedClaude([
            ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]), StackJSON.document(pages: [2], title: "Statement", splitConfidence: 0.4),
                                                StackJSON.document(pages: [3], title: "Manual", from: "Acme"))),
            PipelineHarness.submit("s1", submitInput()),
            PipelineHarness.submit("s2", submitInput()),
            PipelineHarness.submit("s3", submitInput(folder: "", newSubfolder: "Manuals")),
        ])

        let snapshot = try await harness.processor(claude: claude).process(batch)

        #expect(snapshot.status == .needsReview)
        #expect(snapshot.documents == ["doc-1": .filed, "doc-2": .needsReview, "doc-3": .needsReview])
        #expect(FileManager.default.fileExists(atPath: batch.folderURL.path(percentEncoded: false)))
        let reviews = try await harness.events.events(forBatch: batch.id).filter { $0.kind == .needsReview }
        #expect(reviews.map { PipelinePayload.decodeReasons($0.payload[JobPayloadKey.reasons]) } == [[.uncertainSplit(confidence: 0.4)], [.newTopLevelFolder]])
        #expect(reviews.map { $0.payload[JobPayloadKey.folder] } == ["Personal/Finances", ""])
        #expect(!FileManager.default.fileExists(atPath: harness.vault.appending(path: "Manuals").path(percentEncoded: false)))
    }

    @Test func filesPurposeBatchesIntoTheLedgerAndReusesTheRememberedFolder() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let purpose = "2026 taxes, business receipts"
        let batch = try harness.stageBatch(pages: 2, purpose: purpose)
        let fit = #"{"fits":true,"reason":"Office purchase.","tax_year":2026,"tax_category":"business-receipt","expense_category":"office-supplies"}"#
        let claude = ScriptedClaude([
            ScriptedClaude.text(StackJSON.stack(
                StackJSON.document(pages: [1], title: "Office Supplies Receipt", from: "Staples", docDate: "2026-09-02", docType: "receipt",
                                   amount: "84.17", currency: "USD", purposeFit: fit),
                StackJSON.document(pages: [2], title: "Printer Paper Receipt", from: "Amazon", docDate: "2026-09-05", docType: "receipt",
                                   amount: "16.00", currency: "usd", purposeFit: fit)
            )),
            PipelineHarness.submit("s1", submitInput(ledger: "2026 Business Receipts")),
        ])

        let snapshot = try await harness.processor(claude: claude).process(batch)

        #expect(snapshot.status == .filed)
        #expect(await claude.requests.count == 2)
        let ledger = try harness.text("Personal/Finances/2026 Business Receipts.md")
        #expect(ledger.contains("[[2026-09-02 Staples - Office Supplies Receipt]]"))
        #expect(ledger.contains("[[2026-09-05 Amazon - Printer Paper Receipt]]"))
        #expect(ledger.contains("**100.17 USD**"))
        #expect(try await harness.purposes.mapping(for: purpose)
            == PurposeMapping(purpose: purpose, folder: "Personal/Finances", ledgerNoteName: "2026 Business Receipts", createdAt: PipelineHarness.startedAt))
        #expect(try await harness.purposes.recentPurposes() == [purpose])
        #expect(try await harness.kinds(batch.id, document: "doc-1") == [.placementDecided, .pdfWritten, .noteWritten, .ledgerUpdated])
        #expect(try await harness.kinds(batch.id, document: "doc-2") == [.placementDecided, .pdfWritten, .noteWritten, .ledgerUpdated])
        #expect(try harness.text("Personal/Finances/2026-09-05 Amazon - Printer Paper Receipt.md").contains("2026 Business Receipts"))
    }

    @Test func sendsPossibleDuplicatesToReviewWithoutWriting() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let existing = try StackResponse.parse(StackJSON.stack(bill), pages: 1...2).get()[0]
        _ = try Filer(vaultRoot: harness.vault).file(FilingRequest(
            destinationFolder: "Personal/Finances", newSubfolder: nil, pdfData: Data("%PDF".utf8),
            note: NoteContent(baseName: "", analysis: existing, docDate: try #require(CalendarDay("2026-08-28")), docDateEstimated: false,
                              scannedAt: PipelineHarness.startedAt, timeZone: PipelineHarness.utc, filingConfidence: 0.9, pageTexts: ["old"]),
            ledger: nil
        ))
        let batch = try harness.stageBatch(pages: 2)
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(bill)), PipelineHarness.submit("s1", submitInput())])

        let snapshot = try await harness.processor(claude: claude).process(batch)

        #expect(snapshot.documents == ["doc-1": .needsReview])
        let review = try #require(try await harness.events.events(forBatch: batch.id).first { $0.kind == .needsReview })
        #expect(PipelinePayload.decodeReasons(review.payload[JobPayloadKey.reasons]) == [.possibleDuplicate(of: billName)])
        #expect(try harness.vaultFiles("Personal/Finances") == ["\(billName).md", "\(billName).pdf"])
    }

    @Test func usesTheScanDateWhenTheDocumentHasNone() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 1)
        let claude = ScriptedClaude([ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1], docDate: nil))),
                                     PipelineHarness.submit("s1", submitInput(folder: "Work"))])

        _ = try await harness.processor(claude: claude).process(batch)

        let note = try harness.text("Work/2026-09-14 Dominion Energy - Electric Bill.md")
        #expect(note.contains("doc_date_estimated: true"))
    }
}
