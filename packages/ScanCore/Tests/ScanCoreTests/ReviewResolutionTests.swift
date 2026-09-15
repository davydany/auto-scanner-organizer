import Foundation
import Testing
@testable import ScanCore

struct ReviewResolutionTests {
    let fit = #"{"fits":true,"reason":"Office purchase.","tax_year":2026,"tax_category":"business-receipt","expense_category":"office-supplies"}"#

    func reasons(_ harness: PipelineHarness, _ batchID: String, _ documentID: String) async throws -> [ReviewReason] {
        let review = try await harness.events.events(forBatch: batchID).last { $0.kind == .needsReview && $0.documentID == documentID }
        return PipelinePayload.decodeReasons(review?.payload[JobPayloadKey.reasons])
    }

    @Test func filesAReviewedDocumentWithTheOwnersFolderAndCorrections() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let claude = ScriptedClaude([
            ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]), StackJSON.document(pages: [2], title: "Statement", splitConfidence: 0.4))),
            PipelineHarness.submit("s1", submitInput()),
            PipelineHarness.submit("s2", submitInput()),
        ])
        let processor = harness.processor(claude: claude)
        _ = try await processor.process(batch)

        let snapshot = try await processor.resolveReview(batch, documentID: "doc-2",
                                                         resolution: ReviewResolution(folder: "Work", title: "Water Bill", from: "Fairfax Water"))

        #expect(snapshot.status == .filed)
        #expect(snapshot.nextStep == .done)
        #expect(try harness.vaultFiles("Work") == ["2026-08-28 Fairfax Water - Water Bill.md", "2026-08-28 Fairfax Water - Water Bill.pdf"])
        #expect(await claude.requests.count == 3)
        #expect(try await harness.kinds(batch.id, document: "doc-2") == [.placementDecided, .needsReview, .reviewResolved, .pdfWritten, .noteWritten])
        let resolved = try #require(try await harness.events.events(forBatch: batch.id).first { $0.kind == .reviewResolved })
        #expect(resolved.payload[JobPayloadKey.folder] == "Work")
    }

    @Test func stillRequiresTheOwnerToAcceptAPossibleDuplicate() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let first = try harness.stageBatch(id: "2026-09-14-010000", pages: 1)
        let second = try harness.stageBatch(id: "2026-09-14-020000", pages: 1)
        let processor = harness.processor(claude: ScriptedClaude([
            ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]))), PipelineHarness.submit("s1", submitInput()),
            ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]))), PipelineHarness.submit("s2", submitInput()),
        ]))
        _ = try await processor.process(first)
        _ = try await processor.process(second)
        let base = "2026-08-28 Dominion Energy - Electric Bill"
        #expect(try await reasons(harness, second.id, "doc-1") == [.possibleDuplicate(of: base)])

        let refused = try await processor.resolveReview(second, documentID: "doc-1", resolution: ReviewResolution(folder: "Personal/Finances"))
        #expect(refused.documents["doc-1"] == .needsReview)
        #expect(try await reasons(harness, second.id, "doc-1") == [.possibleDuplicate(of: base)])

        let accepted = try await processor.resolveReview(second, documentID: "doc-1",
                                                         resolution: ReviewResolution(folder: "Personal/Finances", acceptPossibleDuplicate: true))
        #expect(accepted.status == .filed)
        #expect(try harness.vaultFiles("Personal/Finances") == ["\(base) (2).md", "\(base) (2).pdf", "\(base).md", "\(base).pdf"])
    }

    @Test func rejectsInvalidResolutionsWithoutRecordingAnything() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let processor = harness.processor(claude: ScriptedClaude([
            ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1]), StackJSON.document(pages: [2], title: "Statement", splitConfidence: 0.4))),
            PipelineHarness.submit("s1", submitInput()), PipelineHarness.submit("s2", submitInput()),
        ]))
        _ = try await processor.process(batch)
        let before = try await harness.events.events(forBatch: batch.id).count

        await #expect(throws: ReviewError.invalidResolution([
            "folder \"../Outside\" must not contain \"..\" or hidden folders.",
            "new_subfolder \"a/b\" must be one folder name without / \\ : * ? \" < > | # ^ [ ], extra spaces, or a leading dot.",
            "title must not be blank.",
            "currency \"dollars\" must be a three-letter code such as USD.",
        ])) {
            try await processor.resolveReview(batch, documentID: "doc-2", resolution: ReviewResolution(
                folder: "../Outside", newSubfolder: "a/b", title: "  ", currency: "dollars"))
        }
        await #expect(throws: ReviewError.documentNotInReview("doc-1")) {
            try await processor.resolveReview(batch, documentID: "doc-1", resolution: ReviewResolution(folder: "Work"))
        }
        await #expect(throws: ReviewError.documentNotInReview("doc-9")) {
            try await processor.resolveReview(batch, documentID: "doc-9", resolution: ReviewResolution(folder: "Work"))
        }
        #expect(try await harness.events.events(forBatch: batch.id).count == before)
    }

    @Test func suppliesAMissingAmountAndRemembersTheOwnersPurposeFolder() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let purpose = "2026 taxes, business receipts"
        let batch = try harness.stageBatch(pages: 1, purpose: purpose)
        let receipt = StackJSON.document(pages: [1], title: "Parking Receipt", from: "City Garage", docDate: "2026-09-03", docType: "receipt", purposeFit: fit)
        let processor = harness.processor(claude: ScriptedClaude([ScriptedClaude.text(StackJSON.stack(receipt)),
                                                                  PipelineHarness.submit("s1", submitInput(ledger: "2026 Business Receipts"))]))
        _ = try await processor.process(batch)
        #expect(try await reasons(harness, batch.id, "doc-1") == [.missingAmount])

        let snapshot = try await processor.resolveReview(batch, documentID: "doc-1", resolution: ReviewResolution(
            folder: "Work", amount: Decimal(string: "12.50"), currency: "usd"))

        #expect(snapshot.status == .filed)
        #expect(try harness.text("Work/2026 Business Receipts.md").contains("| 12.50 USD |"))
        #expect(try await harness.purposes.mapping(for: purpose)?.folder == "Work")
    }

    @Test func neverRemembersAPurposeFolderFromAFilingWithoutALedger() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let purpose = "2026 taxes, business receipts"
        let batch = try harness.stageBatch(pages: 1, purpose: purpose)
        let misfit = #"{"fits":false,"reason":"A personal utility bill.","tax_year":null,"tax_category":null,"expense_category":null}"#
        let processor = harness.processor(claude: ScriptedClaude([ScriptedClaude.text(StackJSON.stack(StackJSON.document(pages: [1], purposeFit: misfit))),
                                                                  PipelineHarness.submit("s1", submitInput(ledger: "2026 Business Receipts"))]))
        _ = try await processor.process(batch)
        #expect(try await reasons(harness, batch.id, "doc-1") == [.purposeMismatch(reason: "A personal utility bill.")])

        let snapshot = try await processor.resolveReview(batch, documentID: "doc-1", resolution: ReviewResolution(folder: "Work"))

        #expect(snapshot.status == .filed)
        #expect(try await harness.purposes.mapping(for: purpose) == nil)
        #expect(try harness.vaultFiles("Work") == ["2026-08-28 Dominion Energy - Electric Bill.md", "2026-08-28 Dominion Energy - Electric Bill.pdf"])
    }

    @Test func filesAnUnreadableBatchOnceTheOwnerDescribesIt() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        let batch = try harness.stageBatch(pages: 2)
        let processor = harness.processor(claude: ScriptedClaude([ScriptedClaude.refusal("cyber")]))
        _ = try await processor.process(batch)

        let snapshot = try await processor.resolveReview(batch, documentID: "doc-1", resolution: ReviewResolution(folder: "Work", title: "Scanned Letter"))

        #expect(snapshot.status == .filed)
        #expect(try harness.vaultFiles("Work") == ["2026-09-14 Scanned Letter.md", "2026-09-14 Scanned Letter.pdf"])
    }

    @Test func retriesOnlyTheLedgerAfterTheOwnerRepairsIt() async throws {
        let harness = try PipelineHarness()
        defer { harness.remove() }
        var euroLedger = LedgerDocument.new(title: "2026 Business Receipts", purpose: "2026 taxes, business receipts", taxYear: 2026)
        try euroLedger.upsert(LedgerRow(date: try #require(CalendarDay("2026-08-01")), from: "Café", amount: 5, currency: "EUR",
                                        category: .meals, documentNoteName: "2026-08-01 Café - Receipt"))
        let ledgerURL = harness.vault.appending(path: "Personal/Finances/2026 Business Receipts.md")
        try Data(euroLedger.render().utf8).write(to: ledgerURL)
        let batch = try harness.stageBatch(pages: 1, purpose: "2026 taxes, business receipts")
        let receipt = StackJSON.document(pages: [1], title: "Office Supplies Receipt", from: "Staples", docDate: "2026-09-02", docType: "receipt",
                                         amount: "84.17", currency: "USD", purposeFit: fit)
        let processor = harness.processor(claude: ScriptedClaude([ScriptedClaude.text(StackJSON.stack(receipt)),
                                                                  PipelineHarness.submit("s1", submitInput(ledger: "2026 Business Receipts"))]))
        _ = try await processor.process(batch)
        #expect(try await reasons(harness, batch.id, "doc-1") == [.ledgerRejected(reason: "mixedCurrency(existing: \"EUR\", new: \"USD\")")])

        try Data(LedgerDocument.new(title: "2026 Business Receipts", purpose: "2026 taxes, business receipts", taxYear: 2026).render().utf8).write(to: ledgerURL)
        let snapshot = try await processor.resolveReview(batch, documentID: "doc-1", resolution: ReviewResolution(folder: "Personal/Finances"))

        #expect(snapshot.status == .filed)
        #expect(try harness.vaultFiles("Personal/Finances").count == 3)
        #expect(try harness.text("Personal/Finances/2026 Business Receipts.md").contains("[[2026-09-02 Staples - Office Supplies Receipt]]"))
    }
}
