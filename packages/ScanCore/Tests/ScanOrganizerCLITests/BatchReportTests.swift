import Foundation
import Testing
@testable import ScanCore
@testable import ScanOrganizerCLI

struct BatchReportTests {
    func event(_ kind: JobEventKind, _ documentID: String? = nil, _ payload: [String: String] = [:]) -> JobEvent {
        JobEvent(batchID: "b1", documentID: documentID, at: Date(timeIntervalSince1970: 0), kind: kind, payload: payload)
    }

    func lines(_ events: [JobEvent]) -> [String] {
        BatchReport.lines(for: BatchProjection.snapshot(batchID: "b1", events: events), events: events)
    }

    @Test func describesFiledReviewAndFailedBatches() {
        let start = [event(.batchAdopted), event(.ocrCompleted)]
        let reasons = PipelinePayload.encodeReasons([.uncertainSplit(confidence: 0.4), .possibleDuplicate(of: "2026-08-28 Bill")])

        #expect(lines(start + [event(.stackRead, nil, [JobPayloadKey.documentIDs: "doc-1,doc-2,doc-3"]), event(.noteWritten, "doc-1"),
                               event(.needsReview, "doc-2", [JobPayloadKey.reasons: reasons])]) == [
            "b1  needs review (1 of 3 documents)",
            "  doc-2  needs review: uncertain split (0.40); possible duplicate of [[2026-08-28 Bill]]",
            "  doc-3  pending",
        ])
        #expect(lines(start + [event(.stackRead, nil, [JobPayloadKey.documentIDs: "doc-1"]), event(.noteWritten, "doc-1"), event(.rawArchived)])
            == ["b1  filed (1 document)"])
        #expect(lines(start + [event(.stackRead, nil, [JobPayloadKey.documentIDs: "doc-1"]),
                               event(.stepFailed, "doc-1", [JobPayloadKey.step: "placeDocuments", JobPayloadKey.message: "offline"])]) == [
            "b1  failed at placeDocuments: offline",
            "  doc-1  failed",
        ])
        #expect(lines([event(.batchAdopted)]) == ["b1  processing"])
    }

    @Test func describesEveryReviewReason() {
        let expected: [(ReviewReason, String)] = [
            (.uncertainSplit(confidence: 0.4), "uncertain split (0.40)"),
            (.splitOnChunkBoundary, "split falls on a 20-page chunk boundary"),
            (.uncertainPlacement(confidence: 0.62), "uncertain folder (0.62)"),
            (.newTopLevelFolder, "would create a new top-level folder"),
            (.purposeMismatch(reason: "Personal purchase."), "doesn't fit the purpose: Personal purchase."),
            (.missingAmount, "no amount with a currency for the ledger"),
            (.possibleDuplicate(of: "X"), "possible duplicate of [[X]]"),
            (.ledgerNeedsAttention, "the ledger note needs attention"),
            (.refused(category: "cyber"), "Claude declined (cyber)"),
            (.validationFailed(message: "bad folder."), "Claude's answer was invalid: bad folder."),
            (.folderMissing(folder: "Gone"), "folder \"Gone\" no longer exists"),
            (.ledgerRejected(reason: "mixed currency"), "the ledger rejected the row: mixed currency"),
        ]
        for (reason, text) in expected {
            #expect(BatchReport.describe(reason) == text)
        }
    }
}
