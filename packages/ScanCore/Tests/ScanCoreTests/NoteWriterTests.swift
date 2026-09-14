import Foundation
import Testing
@testable import ScanCore

struct NoteWriterTests {
    let newYork = TimeZone(identifier: "America/New_York")!
    // 2026-09-14T02:42:03Z == 2026-09-13T22:42:03-04:00
    let scannedAt = Date(timeIntervalSince1970: 1_789_353_723)

    @Test func rendersFullBillNote() {
        let analysis = DocumentAnalysis(
            pages: [1, 2], splitConfidence: 0.93, docType: .bill, title: "Electric Bill", from: "Dominion Energy",
            docDate: CalendarDay("2026-08-28"), summary: "August electric bill, account number 9876543210.",
            tags: ["utilities", "scanned"],
            keyFacts: KeyFacts(amountDue: Decimal(string: "142.18"), dueDate: CalendarDay("2026-09-18"), currency: "USD", accountLast4: "4417"),
            handwritten: [HandwrittenAnnotation(page: 1, rawText: "Paid 9/2", paidOn: CalendarDay("2026-09-02"))]
        )
        let note = NoteContent(
            baseName: "2026-08-28 Dominion Energy - Electric Bill", analysis: analysis, docDate: CalendarDay("2026-08-28")!,
            docDateEstimated: false, scannedAt: scannedAt, timeZone: newYork, filingConfidence: 0.91,
            relatedNotes: ["Primary Residence"], pageTexts: ["DOMINION ENERGY\nAmount due $142.18", "Page two text"]
        )

        let expected = """
        ---
        title: "Electric Bill"
        doc_type: bill
        doc_date: 2026-08-28
        from: "Dominion Energy"
        pages: 2
        scanned_at: 2026-09-13T22:42:03-04:00
        source: "[[2026-08-28 Dominion Energy - Electric Bill.pdf]]"
        tags: ["scanned", "utilities"]
        filing_confidence: 0.91
        related: ["[[Primary Residence]]"]
        amount_due: 142.18
        due_date: 2026-09-18
        currency: "USD"
        account_last4: "4417"
        paid_on: 2026-09-02
        ---

        # Electric Bill, Dominion Energy

        ![[2026-08-28 Dominion Energy - Electric Bill.pdf]]

        ## Summary

        August electric bill, account number ••••3210.

        ## Handwritten notes

        - "Paid 9/2" → paid_on 2026-09-02

        ## Key facts

        - Amount due: 142.18 USD
        - Due date: 2026-09-18
        - Account: ••••4417

        ## Related

        - [[Primary Residence]]

        ## Extracted text

        ### Page 1

        DOMINION ENERGY
        Amount due $142.18

        ### Page 2

        Page two text

        """
        #expect(NoteWriter.render(note) == expected)
    }

    @Test func rendersPurposeFieldsAndEstimatedDate() {
        let analysis = DocumentAnalysis(
            pages: [3], splitConfidence: 0.9, docType: .handwrittenNote, title: "Gutter Cleaning Payment",
            summary: "Paid gutter cleaning.", keyFacts: KeyFacts(amount: Decimal(180), currency: "USD"),
            handwritten: [HandwrittenAnnotation(page: 3, rawText: "pd 9/3 ck #2217 $180", paidOn: CalendarDay("2026-09-03"),
                                                amountPaid: Decimal(180), paymentMethod: "check", checkNumber: "2217")],
            purposeFit: PurposeFit(fits: true, reason: "Home service receipt", taxYear: 2026,
                                   taxCategory: .businessReceipt, expenseCategory: .professionalServices)
        )
        let note = NoteContent(
            baseName: "2026-09-13 Gutter Cleaning Payment", analysis: analysis, docDate: CalendarDay("2026-09-13")!,
            docDateEstimated: true, scannedAt: scannedAt, timeZone: newYork, filingConfidence: 1.0,
            scanPurpose: "2026 taxes, business receipts", ledgerNoteName: "2026 Business Receipts", pageTexts: ["pd 9/3 ck #2217"]
        )
        let output = NoteWriter.render(note)

        #expect(output.contains("doc_date: 2026-09-13\ndoc_date_estimated: true\n"))
        #expect(!output.contains("from:"))
        #expect(output.contains("amount: 180.00\ncurrency: \"USD\"\n"))
        #expect(output.contains("paid_on: 2026-09-03\namount_paid: 180.00\npayment_method: \"check\"\ncheck_number: \"2217\"\n"))
        #expect(output.contains("""
        scan_purpose: "2026 taxes, business receipts"
        tax_year: 2026
        tax_category: business-receipt
        expense_category: professional-services
        ledger: "[[2026 Business Receipts]]"
        ---
        """))
        #expect(output.contains("# Gutter Cleaning Payment\n\n"))
        #expect(output.contains("- \"pd 9/3 ck #2217 $180\" → paid_on 2026-09-03, amount_paid 180.00, payment_method check, check_number 2217"))
        #expect(output.contains("## Key facts\n\n- Amount: 180.00 USD"))
        #expect(!output.contains("## Related"))
    }

    @Test func escapesQuotesInYAMLStrings() {
        let analysis = DocumentAnalysis(pages: [1], splitConfidence: 1, docType: .letter, title: "He said \"hi\"", summary: "x")
        let note = NoteContent(baseName: "b", analysis: analysis, docDate: CalendarDay("2026-01-01")!, docDateEstimated: false,
                               scannedAt: scannedAt, timeZone: newYork, filingConfidence: 0.8, pageTexts: [])
        #expect(NoteWriter.render(note).contains("title: \"He said \\\"hi\\\"\"\n"))
    }

    @Test func formatsMoneyWithTwoDecimals() {
        #expect(Money.format(Decimal(string: "142.18")!) == "142.18")
        #expect(Money.format(Decimal(180)) == "180.00")
        #expect(Money.format(Decimal(string: "1234.567")!) == "1234.57")
    }

    @Test func foldsLineBreaksInSingleLineBodyFields() {
        let analysis = DocumentAnalysis(
            pages: [1], splitConfidence: 1, docType: .letter, title: "Electric\nBill", from: "Dominion\nEnergy",
            summary: "x", handwritten: [HandwrittenAnnotation(page: 1, rawText: "Paid\n9/2")]
        )
        let note = NoteContent(
            baseName: "b", analysis: analysis, docDate: CalendarDay("2026-01-01")!, docDateEstimated: false,
            scannedAt: scannedAt, timeZone: newYork, filingConfidence: 0.8,
            relatedNotes: ["Primary\nResidence"], pageTexts: ["LINE ONE\nLINE TWO"]
        )
        let output = NoteWriter.render(note)

        #expect(output.contains("# Electric Bill, Dominion Energy\n\n"))
        #expect(output.contains("- [[Primary Residence]]"))
        #expect(output.contains("- \"Paid 9/2\""))
        #expect(output.contains("LINE ONE\nLINE TWO"))
    }

    @Test func derivesHandwrittenPropertiesFromOneAnnotation() {
        let analysis = DocumentAnalysis(
            pages: [1], splitConfidence: 1, docType: .letter, title: "t", summary: "x",
            handwritten: [
                HandwrittenAnnotation(page: 1, rawText: "Paid 9/2", paidOn: CalendarDay("2026-09-02")),
                HandwrittenAnnotation(page: 3, rawText: "ck #555 $20", amountPaid: Decimal(20), checkNumber: "555")
            ]
        )
        let note = NoteContent(baseName: "b", analysis: analysis, docDate: CalendarDay("2026-01-01")!, docDateEstimated: false,
                               scannedAt: scannedAt, timeZone: newYork, filingConfidence: 0.8, pageTexts: [])
        let output = NoteWriter.render(note)

        #expect(output.contains("paid_on: 2026-09-02\n"))
        #expect(!output.contains("amount_paid:"))
        #expect(!output.contains("check_number:"))
        #expect(output.contains("- \"Paid 9/2\" → paid_on 2026-09-02"))
        #expect(output.contains("- \"ck #555 $20\" → amount_paid 20.00, check_number 555"))
    }
}
