import Foundation
import Testing
@testable import ScanCore

struct PipelineReviewReasonTests {
    @Test func pipelineReasonsRoundTripThroughScanCoreJSON() throws {
        let reasons: [ReviewReason] = [
            .refused(category: "cyber"),
            .validationFailed(message: "pages 2 and 3 are not covered"),
            .folderMissing(folder: "Personal/Finances"),
            .ledgerRejected(reason: "mixed currencies"),
        ]
        let data = try ScanCoreJSON.encoder().encode(reasons)
        #expect(try ScanCoreJSON.decoder().decode([ReviewReason].self, from: data) == reasons)
    }

    @Test func ledgerAmountRequiresAnAmountAndAValidCurrency() {
        #expect(KeyFacts(amount: Decimal(string: "84.17"), currency: " usd ").ledgerAmount
            == LedgerAmount(amount: Decimal(string: "84.17")!, currency: "USD"))
        #expect(KeyFacts(amount: Decimal(string: "84.17"), currency: nil).ledgerAmount == nil)
        #expect(KeyFacts(amount: Decimal(string: "84.17"), currency: "$").ledgerAmount == nil)
        #expect(KeyFacts(amount: nil, currency: "USD").ledgerAmount == nil)
        #expect(KeyFacts(amountDue: Decimal(string: "10.00"), currency: "USD").ledgerAmount == nil)
    }
}
