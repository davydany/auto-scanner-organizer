import Foundation
import Testing
@testable import ScanCore

extension FilerTests {
    @Test func masksCardNumbersSplitByLineBreaksInTitles() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        let raw = "Card 4111 1111\n1111 1111"

        let result = try filer.file(request(title: raw))

        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(!note.contains("4111 1111"))
        #expect(note.contains("•••• 1111"))
        #expect(!result.baseName.contains("4111"))
        let day = try #require(CalendarDay("2026-08-28"))
        #expect(try filer.findDuplicate(in: result.folderURL, docDate: day, from: "Dominion Energy", title: raw) == result.baseName)
    }

    @Test func masksDigitsJoinedBySanitizingTheFilename() throws {
        let vault = try makeVault()
        defer { vault.remove() }

        let result = try Filer(vaultRoot: vault.url).file(request(title: "Card 4111/1111/1111/1111"))

        #expect(!result.baseName.contains("4111111111111111"))
        #expect(result.baseName.contains("•••• 1111"))
    }

    @Test func rejectsDotPrefixedLedgerNamesBeforeWriting() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        var ledger = receiptLedger(amount: "10.00")
        ledger.noteName = ".Receipts"

        #expect(throws: FilingError.invalidLedgerName(".Receipts")) {
            try Filer(vaultRoot: vault.url).file(request(ledger: ledger))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.url.appending(path: "Personal/Finances").path(percentEncoded: false))
        #expect(names.isEmpty)
    }
}
