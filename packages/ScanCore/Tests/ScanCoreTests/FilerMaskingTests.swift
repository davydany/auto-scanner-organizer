import Foundation
import Testing
@testable import ScanCore

extension FilerTests {
    @Test func masksSensitiveNumbersInClaudesFieldsBeforeNamingAndRendering() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        var ledger = receiptLedger(amount: "25.00")
        ledger.noteName = "Account 000123456789 Receipts"
        ledger.title = "Account 000123456789 Receipts"
        ledger.from = "Chase account 000123456789"
        var sensitive = request(title: "Statement for account 000123456789", from: "Chase", ledger: ledger)
        sensitive.note.analysis.keyFacts.accountLast4 = "4111111111111111"
        sensitive.note.analysis.handwritten = [
            HandwrittenAnnotation(page: 1, rawText: "paid", paymentMethod: "Visa 4111 1111 1111 1111", checkNumber: "4111111111111111"),
        ]

        let result = try filer.file(sensitive)

        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        let ledgerURL = try #require(result.ledgerURL)
        let ledgerText = try String(contentsOf: ledgerURL, encoding: .utf8)
        #expect(!result.baseName.contains("000123456789"))
        #expect(!note.contains("000123456789"))
        #expect(!ledgerURL.lastPathComponent.contains("000123456789"))
        #expect(!ledgerText.contains("000123456789"))
        #expect(!note.contains("4111111111111111"))
        #expect(!note.contains("4111 1111 1111 1111"))
        #expect(note.contains("account_last4: \"1111\""))
        let day = CalendarDay("2026-08-28")!
        #expect(try filer.findDuplicate(in: result.folderURL, docDate: day, from: "Chase",
                                         title: "Statement for account 000123456789") == result.baseName)
        // Retrying the ledger step with the unmasked filing reaches the same, masked ledger note.
        #expect(try filer.updateLedger(ledger, documentNoteName: result.baseName, docDate: day,
                                       in: ledgerURL.deletingLastPathComponent()) == ledgerURL)
    }

    @Test func keepsOnlyTheDigitsOfAShortAccountLast4AndDropsOneWithoutDigits() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        var short = request(title: "Short")
        short.note.analysis.keyFacts.accountLast4 = "x-12"
        var none = request(title: "None")
        none.note.analysis.keyFacts.accountLast4 = "N/A"

        #expect(try String(contentsOf: filer.file(short).noteURL, encoding: .utf8).contains("account_last4: \"12\""))
        #expect(try !String(contentsOf: filer.file(none).noteURL, encoding: .utf8).contains("account_last4"))
    }

    @Test func checksLedgerValidityUnderTheMaskedLedgerName() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let folder = vault.url.appending(path: "Personal/Finances")
        try Data("# Receipts without markers\n".utf8).write(to: folder.appending(path: "Account ••••6789 Receipts.md"))

        #expect(!Filer(vaultRoot: vault.url).ledgerIsValid(in: folder, noteName: "Account 000123456789 Receipts"))
    }

    @Test func treatsAnEmptySenderAsNoSenderWhenFindingDuplicates() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        let day = CalendarDay("2026-08-28")!
        let result = try filer.file(request(from: nil))

        #expect(try filer.findDuplicate(in: result.folderURL, docDate: day, from: "", title: "Electric Bill") == result.baseName)
        #expect(try filer.findDuplicate(in: result.folderURL, docDate: day, from: "   ", title: "Electric Bill") == result.baseName)

        let handEdited = "---\ntitle: \"Gas Bill\"\ndoc_date: 2026-08-28\nfrom: \"\"\n---\n# Gas Bill\n"
        try Data(handEdited.utf8).write(to: result.folderURL.appending(path: "Hand edited.md"))
        #expect(try filer.findDuplicate(in: result.folderURL, docDate: day, from: nil, title: "Gas Bill") == "Hand edited")
    }
}
