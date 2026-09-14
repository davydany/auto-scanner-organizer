import Foundation
import Testing
@testable import ScanCore

struct DocumentAnalysisTests {
    static let stackJSON = """
    {
      "documents": [
        {
          "pages": [1, 2],
          "split_confidence": 0.93,
          "doc_type": "bill",
          "title": "Electric Bill",
          "from": "Dominion Energy",
          "doc_date": "2026-08-28",
          "summary": "August electric bill.",
          "tags": ["utilities", "primary-residence"],
          "key_facts": { "amount_due": 142.18, "due_date": "2026-09-18", "account_last4": "4417" },
          "handwritten": [ { "page": 1, "raw_text": "Paid 9/2", "paid_on": "2026-09-02" } ],
          "purpose_fit": null
        },
        {
          "pages": [3],
          "split_confidence": 0.61,
          "doc_type": "handwritten-note",
          "title": "Gutter Cleaning Payment",
          "from": null,
          "doc_date": null,
          "summary": "Note about gutter cleaning.",
          "tags": [],
          "key_facts": {},
          "handwritten": [
            { "page": 3, "raw_text": "pd 9/3 ck #2217 $180", "paid_on": "2026-09-03",
              "amount_paid": 180.00, "payment_method": "check", "check_number": "2217" }
          ],
          "purpose_fit": { "fits": true, "reason": "Home expense", "tax_year": 2026,
                           "tax_category": "business-receipt", "expense_category": "professional-services" }
        }
      ]
    }
    """

    @Test func decodesStackAnalysisFromSnakeCaseJSON() throws {
        let stack = try ScanCoreJSON.decoder().decode(StackAnalysis.self, from: Data(Self.stackJSON.utf8))
        #expect(stack.documents.count == 2)

        let bill = stack.documents[0]
        #expect(bill.pages == [1, 2])
        #expect(bill.docType == .bill)
        #expect(bill.docDate == CalendarDay("2026-08-28"))
        #expect(bill.keyFacts.amountDue == Decimal(string: "142.18"))
        #expect(bill.keyFacts.accountLast4 == "4417")
        #expect(bill.handwritten.first?.paidOn == CalendarDay("2026-09-02"))
        #expect(bill.purposeFit == nil)

        let note = stack.documents[1]
        #expect(note.docType == .handwrittenNote)
        #expect(note.from == nil)
        #expect(note.handwritten.first?.checkNumber == "2217")
        #expect(note.purposeFit?.taxCategory == .businessReceipt)
        #expect(note.purposeFit?.expenseCategory == .professionalServices)
    }

    @Test func rejectsUnknownDocType() {
        let json = Self.stackJSON.replacingOccurrences(of: "\"bill\"", with: "\"invoice\"")
        #expect(throws: DecodingError.self) {
            try ScanCoreJSON.decoder().decode(StackAnalysis.self, from: Data(json.utf8))
        }
    }

    @Test func enumRawValuesMatchSpec() {
        #expect(DocType.allCases.map(\.rawValue) == [
            "bill", "statement", "receipt", "tax", "insurance", "medical", "legal",
            "letter", "notice", "manual", "handwritten-note", "other",
        ])
        #expect(TaxCategory.allCases.map(\.rawValue) == [
            "business-receipt", "business-income", "personal-deduction", "medical",
            "charitable", "property-tax", "other",
        ])
        #expect(ExpenseCategory.allCases.map(\.rawValue) == [
            "office-supplies", "travel", "meals", "software", "equipment",
            "utilities", "professional-services", "other",
        ])
    }

    @Test func decodesPlacement() throws {
        let json = """
        { "folder": "Personal/Properties/Primary Residence", "new_subfolder": "Utilities",
          "related_notes": ["Primary Residence"], "confidence": 0.91, "reason": "Utility bill for the home.",
          "alternatives": [ { "folder": "Personal/Finances", "confidence": 0.4 } ] }
        """
        let placement = try ScanCoreJSON.decoder().decode(Placement.self, from: Data(json.utf8))
        #expect(placement.newSubfolder == "Utilities")
        #expect(placement.relatedNotes == ["Primary Residence"])
        #expect(placement.alternatives == [PlacementAlternative(folder: "Personal/Finances", confidence: 0.4)])
    }
}
