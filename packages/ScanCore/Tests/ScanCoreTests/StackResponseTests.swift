import Foundation
import Testing
@testable import ScanCore

struct StackResponseTests {
    func failureMessages(_ text: String, pages: ClosedRange<Int>) -> [String] {
        if case .failure(let error) = StackResponse.parse(text, pages: pages) { return error.messages }
        Issue.record("expected a validation failure")
        return []
    }

    @Test func mapsAValidStackToDocumentAnalyses() throws {
        let handwriting = #"[{"page":2,"raw_text":"Paid 9/2 ck 1042","paid_on":"2026-09-02","amount_paid":"142.18","payment_method":"check","check_number":"1042"}]"#
        let fit = #"{"fits":true,"reason":"Home office utility.","tax_year":2026,"tax_category":"business-receipt","expense_category":"utilities"}"#
        let text = StackJSON.stack(
            StackJSON.document(pages: [1, 2], amount: "142.18", currency: "USD", handwritten: handwriting, purposeFit: fit),
            StackJSON.document(pages: [3], title: "Receipt", from: nil, docDate: nil, splitConfidence: 0.6, docType: "receipt")
        )

        let documents = try StackResponse.parse(text, pages: 1...3).get()

        #expect(documents == [
            DocumentAnalysis(
                pages: [1, 2], splitConfidence: 0.95, docType: .bill, title: "Electric Bill", from: "Dominion Energy",
                docDate: CalendarDay("2026-08-28"), summary: "A short summary.", tags: ["electric-bill", "utilities"],
                keyFacts: KeyFacts(amount: Decimal(string: "142.18"), currency: "USD", accountLast4: "7890"),
                handwritten: [HandwrittenAnnotation(page: 2, rawText: "Paid 9/2 ck 1042", paidOn: CalendarDay("2026-09-02"),
                                                    amountPaid: Decimal(string: "142.18"), paymentMethod: "check", checkNumber: "1042")],
                purposeFit: PurposeFit(fits: true, reason: "Home office utility.", taxYear: 2026, taxCategory: .businessReceipt, expenseCategory: .utilities)
            ),
            DocumentAnalysis(pages: [3], splitConfidence: 0.6, docType: .receipt, title: "Receipt", summary: "A short summary.",
                             tags: ["electric-bill", "utilities"], keyFacts: KeyFacts(accountLast4: "7890")),
        ])
    }

    @Test func reportsGapsOverlapsAndNonConsecutivePages() {
        let messages = failureMessages(StackJSON.stack(StackJSON.document(pages: [1, 3]), StackJSON.document(pages: [3])), pages: 1...4)

        #expect(messages == [
            "Document 1 pages [1, 3] are not consecutive.",
            "The documents must cover pages 1–4 exactly once, in order; they cover [1, 3, 3].",
        ])
    }

    @Test func reportsEveryInvalidValue() {
        let handwriting = #"[{"page":9,"raw_text":"x","paid_on":"9/2","amount_paid":"1,000","payment_method":null,"check_number":null}]"#
        let fit = #"{"fits":true,"reason":"r","tax_year":26,"tax_category":"income","expense_category":"food"}"#
        let text = StackJSON.stack(StackJSON.document(pages: [1], docDate: "08/28/2026", splitConfidence: 1.5, docType: "invoice",
                                                     amount: "$12", handwritten: handwriting, purposeFit: fit))

        #expect(failureMessages(text, pages: 1...1) == [
            "Document 1 split_confidence must be between 0 and 1.",
            "Document 1 has an unknown doc_type \"invoice\".",
            "Document 1 doc_date \"08/28/2026\" is not YYYY-MM-DD.",
            "Document 1 key_facts.amount \"$12\" is not a plain decimal.",
            "Document 1 has handwriting on page 9, outside its pages.",
            "Document 1 handwritten paid_on \"9/2\" is not YYYY-MM-DD.",
            "Document 1 handwritten amount_paid \"1,000\" is not a plain decimal.",
            "Document 1 purpose_fit.tax_year 26 is not a plausible year.",
            "Document 1 has an unknown tax_category \"income\".",
            "Document 1 has an unknown expense_category \"food\".",
        ])
    }

    @Test func reportsUndecodableAndEmptyResponses() {
        let undecodable = failureMessages("not json", pages: 1...1)
        #expect(undecodable.count == 1)
        #expect(undecodable.first?.hasPrefix("The response did not match the schema:") == true)
        #expect(failureMessages(#"{"documents":[]}"#, pages: 1...2) == ["The response contained no documents."])
    }

    @Test(arguments: [("84.17", "84.17"), ("-3", "-3"), ("0.5", "0.5")])
    func parsesPlainDecimals(_ text: String, _ expected: String) {
        #expect(StackResponse.plainDecimal(text) == Decimal(string: expected))
    }

    @Test(arguments: ["", "$1", "1,000", "1.2.3", ".5", "5.", "1e3", "١٢"])
    func rejectsOtherNumberFormats(_ text: String) {
        #expect(StackResponse.plainDecimal(text) == nil)
    }
}
