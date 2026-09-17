import Testing
@testable import ScanCore

struct ReviewApprovalTests {
    @Test(arguments: [false, true])
    func classifiesEveryReviewReason(acceptPossibleDuplicate: Bool) {
        let approval = ReviewApproval(acceptPossibleDuplicate: acceptPossibleDuplicate)
        let table: [(reason: ReviewReason, stillBlocks: Bool)] = [
            (.missingAmount, true),
            (.ledgerNeedsAttention, true),
            (.folderMissing(folder: "Work"), true),
            (.ledgerRejected(reason: "mixed currency"), true),
            (.possibleDuplicate(of: "2026-08-28 Dominion Energy - Electric Bill"), !acceptPossibleDuplicate),
            (.uncertainSplit(confidence: 0.4), false),
            (.splitOnChunkBoundary, false),
            (.uncertainPlacement(confidence: 0.4), false),
            (.newTopLevelFolder, false),
            (.purposeMismatch(reason: "A personal bill."), false),
            (.refused(category: "cyber"), false),
            (.validationFailed(message: "folder is missing."), false),
        ]

        #expect(table.count == 12)
        for row in table {
            #expect(approval.stillBlocks(row.reason) == row.stillBlocks, "\(row.reason)")
        }
    }
}
