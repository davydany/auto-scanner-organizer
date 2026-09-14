import Foundation
import Testing
@testable import ScanCore

/// Forwards to a real `LocalFileSystem`, except that writing a `.md` file always fails —
/// used to simulate a note-write failure after the PDF has already been written.
private struct FailingNoteWritesFileSystem: FileSystem {
    private let inner = LocalFileSystem()

    func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { inner.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try inner.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try inner.readData(at: url) }

    func writeAtomically(_ data: Data, to url: URL) throws {
        if url.pathExtension == "md" { throw CocoaError(.fileWriteNoPermission) }
        try inner.writeAtomically(data, to: url)
    }

    func createNewFile(_ data: Data, at url: URL) throws {
        if url.pathExtension == "md" { throw CocoaError(.fileWriteNoPermission) }
        try inner.createNewFile(data, at: url)
    }

    func moveItem(at source: URL, to destination: URL) throws { try inner.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try inner.removeItem(at: url) }
}

struct FilerTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    func makeVault() throws -> TemporaryDirectory {
        let temp = try TemporaryDirectory()
        for folder in ["Personal/Finances", "Personal/Properties/Primary Residence"] {
            try FileManager.default.createDirectory(at: temp.url.appending(path: folder), withIntermediateDirectories: true)
        }
        return temp
    }

    /// A `TemporaryDirectory` with the vault nested under `Vault`, so `Outside` (a sibling) is
    /// genuinely outside the vault root rather than merely outside its tracked subfolders.
    struct VaultWithOutsideSibling {
        let temp: TemporaryDirectory
        let vault: URL
        let outside: URL
    }

    func makeVaultWithOutsideSibling() throws -> VaultWithOutsideSibling {
        let temp = try TemporaryDirectory()
        let vault = temp.url.appending(path: "Vault")
        let outside = temp.url.appending(path: "Outside")
        for folder in ["Personal/Finances"] {
            try FileManager.default.createDirectory(at: vault.appending(path: folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return VaultWithOutsideSibling(temp: temp, vault: vault, outside: outside)
    }

    func request(title: String = "Electric Bill", from: String? = "Dominion Energy", folder: String = "Personal/Finances",
                 newSubfolder: String? = nil, ledger: LedgerFiling? = nil) -> FilingRequest {
        let analysis = DocumentAnalysis(pages: [1], splitConfidence: 0.9, docType: .bill, title: title, from: from,
                                        docDate: CalendarDay("2026-08-28"), summary: "Summary.")
        let note = NoteContent(baseName: "", analysis: analysis, docDate: CalendarDay("2026-08-28")!, docDateEstimated: false,
                               scannedAt: Date(timeIntervalSince1970: 1_789_353_723), timeZone: newYork,
                               filingConfidence: 0.9, pageTexts: ["text"])
        return FilingRequest(destinationFolder: folder, newSubfolder: newSubfolder, pdfData: Data("%PDF-fake".utf8),
                             note: note, ledger: ledger)
    }

    func receiptLedger(amount: String) -> LedgerFiling {
        LedgerFiling(noteName: "2026 Business Receipts", title: "2026 Business Receipts", purpose: "2026 taxes, business receipts",
                     taxYear: 2026, from: "Dominion Energy", amount: Decimal(string: amount)!, currency: "USD", category: .utilities)
    }

    @Test func filesPDFAndNoteIntoExistingFolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)

        let result = try filer.file(request())

        #expect(result.baseName == "2026-08-28 Dominion Energy - Electric Bill")
        #expect(!result.createdFolder)
        #expect(result.pdfURL.lastPathComponent == "2026-08-28 Dominion Energy - Electric Bill.pdf")
        #expect(try Data(contentsOf: result.pdfURL) == Data("%PDF-fake".utf8))
        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(note.contains("source: \"[[2026-08-28 Dominion Energy - Electric Bill.pdf]]\""))
        #expect(result.ledgerURL == nil)
    }

    @Test func createsNewSubfolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let result = try Filer(vaultRoot: vault.url)
            .file(request(folder: "Personal/Properties/Primary Residence", newSubfolder: "Utilities"))
        #expect(result.createdFolder)
        #expect(result.folderURL.path(percentEncoded: false).hasSuffix("/Primary Residence/Utilities"))
        #expect(FileManager.default.fileExists(atPath: result.noteURL.path(percentEncoded: false)))
    }

    @Test func appendsCounterOnNameCollision() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let existing = vault.url.appending(path: "Personal/Finances/2026-08-28 Dominion Energy - Electric Bill.pdf")
        try Data("old".utf8).write(to: existing)
        let result = try Filer(vaultRoot: vault.url).file(request())
        #expect(result.baseName == "2026-08-28 Dominion Energy - Electric Bill (2)")
        #expect(try Data(contentsOf: existing) == Data("old".utf8))
    }

    @Test(arguments: ["a/b", "..", "", ".hidden"])
    func rejectsInvalidSubfolders(_ subfolder: String) throws {
        let vault = try makeVault()
        defer { vault.remove() }
        #expect(throws: FilingError.invalidSubfolder(subfolder)) {
            try Filer(vaultRoot: vault.url).file(request(newSubfolder: subfolder))
        }
    }

    @Test func rejectsMissingDestinationFolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        #expect(throws: FilingError.folderMissing("Personal/Nope")) {
            try Filer(vaultRoot: vault.url).file(request(folder: "Personal/Nope"))
        }
    }

    @Test func rejectsDestinationOutsideVault() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        #expect(throws: PathGuardError.escapesRoot("../elsewhere")) {
            try Filer(vaultRoot: vault.url).file(request(folder: "../elsewhere"))
        }
    }

    @Test func findsDuplicateByDateSenderAndTitleIgnoringLedgers() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        let result = try filer.file(request(ledger: receiptLedger(amount: "142.18")))
        let folder = result.folderURL
        let day = CalendarDay("2026-08-28")!

        #expect(try filer.findDuplicate(in: folder, docDate: day, from: "Dominion Energy", title: "Electric Bill") == result.baseName)
        #expect(try filer.findDuplicate(in: folder, docDate: day, from: "Dominion Energy", title: "Gas Bill") == nil)
        #expect(try filer.findDuplicate(in: folder, docDate: day, from: nil, title: "Electric Bill") == nil)
        #expect(try filer.findDuplicate(in: vault.url.appending(path: "Missing"), docDate: day, from: nil, title: "x") == nil)
    }

    @Test func createsThenUpdatesPurposeLedger() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)

        let first = try filer.file(request(title: "Electric Bill", ledger: receiptLedger(amount: "142.18")))
        let second = try filer.file(request(title: "Water Bill", ledger: receiptLedger(amount: "40.00")))

        let ledgerURL = try #require(second.ledgerURL)
        #expect(ledgerURL.lastPathComponent == "2026 Business Receipts.md")
        let ledger = try LedgerDocument.parse(try String(contentsOf: ledgerURL, encoding: .utf8))
        #expect(ledger.rows.map(\.documentNoteName).sorted() == [first.baseName, second.baseName].sorted())
        #expect(ledger.total == Decimal(string: "182.18"))
        #expect(try String(contentsOf: first.noteURL, encoding: .utf8).contains("ledger: \"[[2026 Business Receipts]]\""))
        #expect(filer.ledgerIsValid(in: first.folderURL, noteName: "2026 Business Receipts"))
    }

    @Test func reportsLedgerFailureAfterWritingDocument() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let folder = vault.url.appending(path: "Personal/Finances")
        try Data("# Receipts without markers\n".utf8).write(to: folder.appending(path: "2026 Business Receipts.md"))
        let filer = Filer(vaultRoot: vault.url)
        #expect(!filer.ledgerIsValid(in: folder, noteName: "2026 Business Receipts"))

        do {
            _ = try filer.file(request(ledger: receiptLedger(amount: "10.00")))
            Issue.record("Expected ledgerUpdateFailed")
        } catch let FilingError.ledgerUpdateFailed(ledgerError, result) {
            #expect(ledgerError == .markersMissing)
            #expect(FileManager.default.fileExists(atPath: result.pdfURL.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: result.noteURL.path(percentEncoded: false)))
        }
    }

    @Test func ignoresDuplicateCandidatesSymlinkedFromOutsideVault() throws {
        let scenario = try makeVaultWithOutsideSibling()
        let (vault, outside) = (scenario.vault, scenario.outside)
        defer { scenario.temp.remove() }
        let realNote = """
        ---
        title: "Electric Bill"
        doc_date: 2026-08-28
        from: "Dominion Energy"
        ---
        # Electric Bill
        """
        try Data(realNote.utf8).write(to: outside.appending(path: "real.md"))
        let financesFolder = vault.appending(path: "Personal/Finances")
        try FileManager.default.createSymbolicLink(at: financesFolder.appending(path: "linked.md"),
                                                    withDestinationURL: outside.appending(path: "real.md"))
        let filer = Filer(vaultRoot: vault)

        let duplicate = try filer.findDuplicate(in: financesFolder, docDate: CalendarDay("2026-08-28")!,
                                                 from: "Dominion Energy", title: "Electric Bill")
        #expect(duplicate == nil)
    }

    @Test func treatsLedgerSymlinkedFromOutsideVaultAsInvalid() throws {
        let scenario = try makeVaultWithOutsideSibling()
        let (vault, outside) = (scenario.vault, scenario.outside)
        defer { scenario.temp.remove() }
        let ledgerContent = LedgerDocument.new(title: "2026 Business Receipts", purpose: "p", taxYear: 2026).render()
        let outsideLedgerURL = outside.appending(path: "ledger.md")
        try Data(ledgerContent.utf8).write(to: outsideLedgerURL)
        let financesFolder = vault.appending(path: "Personal/Finances")
        try FileManager.default.createSymbolicLink(at: financesFolder.appending(path: "2026 Business Receipts.md"),
                                                    withDestinationURL: outsideLedgerURL)
        let filer = Filer(vaultRoot: vault)

        #expect(!filer.ledgerIsValid(in: financesFolder, noteName: "2026 Business Receipts"))

        let beforeBytes = try Data(contentsOf: outsideLedgerURL)
        do {
            _ = try filer.file(request(folder: "Personal/Finances", ledger: receiptLedger(amount: "10.00")))
            Issue.record("Expected ledgerUpdateFailed")
        } catch let FilingError.ledgerUpdateFailed(ledgerError, _) {
            #expect(ledgerError == .markersMissing)
        }
        let afterBytes = try Data(contentsOf: outsideLedgerURL)
        #expect(beforeBytes == afterBytes)
    }

    @Test func skipsNonUTF8NotesInDuplicateCheck() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let folder = vault.url.appending(path: "Personal/Finances")
        let invalidUTF8 = Data([0xFF, 0xFE, 0x00, 0x2D])
        try invalidUTF8.write(to: folder.appending(path: "binary.md"))
        let filer = Filer(vaultRoot: vault.url)

        let duplicate = try filer.findDuplicate(in: folder, docDate: CalendarDay("2026-08-28")!, from: nil, title: "x")
        #expect(duplicate == nil)

        try invalidUTF8.write(to: folder.appending(path: "2026 Business Receipts.md"))
        #expect(!filer.ledgerIsValid(in: folder, noteName: "2026 Business Receipts"))
    }

    @Test func removesOrphanPDFWhenNoteWriteFails() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url, fileSystem: FailingNoteWritesFileSystem())

        #expect(throws: CocoaError.self) {
            _ = try filer.file(request())
        }

        let financesFolder = vault.url.appending(path: "Personal/Finances")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: financesFolder.path(percentEncoded: false))
        #expect(!remaining.contains { $0.hasSuffix(".pdf") })
    }

    @Test func findsDuplicateWhenTitleAndSenderContainLineBreaks() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        let result = try filer.file(request(title: "Electric\nBill", from: "Dominion\nEnergy"))

        let duplicate = try filer.findDuplicate(in: result.folderURL, docDate: CalendarDay("2026-08-28")!,
                                                 from: "Dominion\nEnergy", title: "Electric\nBill")
        #expect(duplicate == result.baseName)
    }

    @Test func findsDuplicateAcrossLineBreakStylesAndSpacing() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        let result = try filer.file(request(title: "Electric\r\n\r\nBill ", from: "\nDominion\nEnergy"))

        #expect(try filer.findDuplicate(in: result.folderURL, docDate: CalendarDay("2026-08-28")!,
                                         from: "\nDominion\nEnergy", title: "Electric\r\n\r\nBill ") == result.baseName)
        #expect(try filer.findDuplicate(in: result.folderURL, docDate: CalendarDay("2026-08-28")!,
                                         from: "Dominion Energy", title: "Electric Bill") == result.baseName)
        #expect(try filer.findDuplicate(in: result.folderURL, docDate: CalendarDay("2026-08-28")!,
                                         from: "Dominion Energy", title: "Electric Bills") == nil)
    }
}
