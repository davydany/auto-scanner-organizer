import Foundation
import Testing
@testable import ScanCore

struct LedgerTests {
    let staples = LedgerRow(date: CalendarDay("2026-09-02")!, from: "Staples", amount: Decimal(string: "84.17")!,
                            currency: "USD", category: .officeSupplies, documentNoteName: "2026-09-02 Staples - Receipt")
    let delta = LedgerRow(date: CalendarDay("2026-09-10")!, from: "Delta", amount: Decimal(string: "412.60")!,
                          currency: "USD", category: .travel, documentNoteName: "2026-09-10 Delta - Flight Receipt")

    @Test func newLedgerRendersEmptyManagedTable() {
        let expected = """
        ---
        type: ledger
        scan_purpose: "2026 taxes, business receipts"
        tax_year: 2026
        ---

        # 2026 Business Receipts

        Documents filed by Auto Scanner Organizer for this purpose.

        <!-- auto-scanner:ledger:start -->
        | Date | From | Amount | Category | Document |
        |---|---|---|---|---|
        | **Total** |  | **0.00** |  |  |
        <!-- auto-scanner:ledger:end -->

        """
        let ledger = LedgerDocument.new(title: "2026 Business Receipts", purpose: "2026 taxes, business receipts", taxYear: 2026)
        #expect(ledger.render() == expected)
    }

    @Test func upsertSortsRowsByDateAndTotals() throws {
        var ledger = LedgerDocument.new(title: "T", purpose: "p", taxYear: nil)
        try ledger.upsert(delta)
        try ledger.upsert(staples)
        #expect(ledger.rows.map(\.from) == ["Staples", "Delta"])
        #expect(ledger.total == Decimal(string: "496.77"))
        #expect(ledger.render().contains("""
        | 2026-09-02 | Staples | 84.17 USD | office-supplies | [[2026-09-02 Staples - Receipt]] |
        | 2026-09-10 | Delta | 412.60 USD | travel | [[2026-09-10 Delta - Flight Receipt]] |
        | **Total** |  | **496.77 USD** |  |  |
        """))
    }

    @Test func upsertIsIdempotentPerDocument() throws {
        var ledger = LedgerDocument.new(title: "T", purpose: "p", taxYear: nil)
        try ledger.upsert(staples)
        var corrected = staples
        corrected.amount = Decimal(string: "90.00")!
        try ledger.upsert(corrected)
        try ledger.upsert(corrected)
        #expect(ledger.rows == [corrected])
    }

    @Test func parseAndRenderPreserveTextOutsideMarkers() throws {
        let original = """
        # My receipts

        Owner notes above the table.

        <!-- auto-scanner:ledger:start -->
        | Date | From | Amount | Category | Document |
        |---|---|---|---|---|
        | 2026-09-10 | Delta | 412.60 USD | travel | [[2026-09-10 Delta - Flight Receipt]] |
        | **Total** |  | **412.60 USD** |  |  |
        <!-- auto-scanner:ledger:end -->

        Owner notes below the table.

        """
        var ledger = try LedgerDocument.parse(original)
        #expect(ledger.rows == [delta])
        #expect(ledger.render() == original)

        try ledger.upsert(staples)
        let updated = ledger.render()
        #expect(updated.hasPrefix("# My receipts\n\nOwner notes above the table.\n\n<!-- auto-scanner:ledger:start -->\n"))
        #expect(updated.hasSuffix("<!-- auto-scanner:ledger:end -->\n\nOwner notes below the table.\n"))
        #expect(try LedgerDocument.parse(updated).rows == [staples, delta])
    }

    @Test func rejectsMissingOrDuplicatedMarkers() {
        #expect(throws: LedgerError.markersMissing) { try LedgerDocument.parse("# No table here\n") }
        let doubled = "\(LedgerDocument.startMarker)\n\(LedgerDocument.endMarker)\n\(LedgerDocument.startMarker)\n\(LedgerDocument.endMarker)\n"
        #expect(throws: LedgerError.markersDuplicated) { try LedgerDocument.parse(doubled) }
        let reversed = "\(LedgerDocument.endMarker)\n\(LedgerDocument.startMarker)\n"
        #expect(throws: LedgerError.markersMissing) { try LedgerDocument.parse(reversed) }
    }

    @Test func rejectsUnparseableRows() {
        let badRow = "| 2026-13-01 | X | 1.00 USD | travel | [[a]] |"
        let markdown = "\(LedgerDocument.startMarker)\n\(badRow)\n\(LedgerDocument.endMarker)\n"
        #expect(throws: LedgerError.unparseableRow(badRow)) { try LedgerDocument.parse(markdown) }
    }

    @Test func rejectsMixedCurrencies() throws {
        var ledger = LedgerDocument.new(title: "T", purpose: "p", taxYear: nil)
        try ledger.upsert(staples)
        var euros = delta
        euros.currency = "EUR"
        #expect(throws: LedgerError.mixedCurrency(existing: "USD", new: "EUR")) { try ledger.upsert(euros) }
    }

    @Test func foldsLineBreaksInRenderedCells() throws {
        var ledger = LedgerDocument.new(title: "2026\nReceipts", purpose: "p", taxYear: nil)
        var row = staples
        row.from = "Staples\nInc"
        try ledger.upsert(row)
        #expect(ledger.render().contains("# 2026 Receipts\n"))
        #expect(ledger.render().contains(
            "| 2026-09-02 | Staples Inc | 84.17 USD | office-supplies | [[2026-09-02 Staples - Receipt]] |"
        ))
        #expect(try LedgerDocument.parse(ledger.render()).rows.first?.from == "Staples Inc")
    }
}
