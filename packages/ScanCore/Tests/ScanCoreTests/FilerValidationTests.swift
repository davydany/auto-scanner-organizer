import Foundation
import Testing
@testable import ScanCore

/// Forwards to a real `LocalFileSystem`, except that a replacing write to a file with the given name fails —
/// used to simulate an I/O failure while writing the ledger, after the PDF and note were created.
private struct FailingLedgerWritesFileSystem: FileSystem {
    let ledgerFileName: String
    private let inner = LocalFileSystem()

    init(ledgerFileName: String) {
        self.ledgerFileName = ledgerFileName
    }

    func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { inner.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try inner.contentsOfDirectory(at: url) }
    func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try inner.readData(at: url) }

    func writeAtomically(_ data: Data, to url: URL) throws {
        if url.lastPathComponent == ledgerFileName { throw CocoaError(.fileWriteNoPermission) }
        try inner.writeAtomically(data, to: url)
    }

    func createNewFile(_ data: Data, at url: URL) throws { try inner.createNewFile(data, at: url) }
    func moveItem(at source: URL, to destination: URL) throws { try inner.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try inner.removeItem(at: url) }
}

extension FilerTests {
    /// Names of every regular file anywhere under `root`, hidden files included.
    func regularFiles(in root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var files: [String] = []
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files.append(url.lastPathComponent)
        }
        return files
    }

    @Test func keepsTheFilingResultWhenTheLedgerWriteFailsWithAnIOError() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url, fileSystem: FailingLedgerWritesFileSystem(ledgerFileName: "2026 Business Receipts.md"))

        do {
            _ = try filer.file(request(ledger: receiptLedger(amount: "10.00")))
            Issue.record("Expected ledgerUpdateFailed")
        } catch let FilingError.ledgerUpdateFailed(failure, result) {
            guard case .io = failure else {
                Issue.record("Expected an io failure, got \(failure)")
                return
            }
            #expect(FileManager.default.fileExists(atPath: result.pdfURL.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: result.noteURL.path(percentEncoded: false)))
        }
    }

    @Test(arguments: [".obsidian", "Personal/.trash"])
    func rejectsHiddenDestinationFolders(_ folder: String) throws {
        let vault = try makeVault()
        defer { vault.remove() }
        try FileManager.default.createDirectory(at: vault.url.appending(path: folder), withIntermediateDirectories: true)

        #expect(throws: FilingError.hiddenFolder(folder)) {
            try Filer(vaultRoot: vault.url).file(request(folder: folder))
        }
        #expect(try regularFiles(in: vault.url).isEmpty)
    }

    @Test func rejectsAHiddenLedgerFolder() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        try FileManager.default.createDirectory(at: vault.url.appending(path: ".obsidian"), withIntermediateDirectories: true)

        #expect(throws: FilingError.hiddenFolder(".obsidian")) {
            try Filer(vaultRoot: vault.url).file(request(ledger: receiptLedger(amount: "1.00", folder: ".obsidian")))
        }
        #expect(try regularFiles(in: vault.url).isEmpty)
    }

    @Test func updatesTheLedgerInThePurposeFolderRatherThanBesideTheDocument() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        try FileManager.default.createDirectory(at: vault.url.appending(path: "Personal/Finances/Taxes"), withIntermediateDirectories: true)

        let result = try Filer(vaultRoot: vault.url)
            .file(request(ledger: receiptLedger(amount: "142.18", folder: "Personal/Finances/Taxes")))

        let ledgerURL = try #require(result.ledgerURL)
        #expect(ledgerURL.path(percentEncoded: false).hasSuffix("/Personal/Finances/Taxes/2026 Business Receipts.md"))
        let ledger = try LedgerDocument.parse(try String(contentsOf: ledgerURL, encoding: .utf8))
        #expect(ledger.rows.map(\.documentNoteName) == [result.baseName])
        #expect(!FileManager.default.fileExists(atPath: result.folderURL.appending(path: "2026 Business Receipts.md").path(percentEncoded: false)))
        #expect(try String(contentsOf: result.noteURL, encoding: .utf8).contains("ledger: \"[[2026 Business Receipts]]\""))
    }

    @Test func acceptsALedgerFolderThatIsTheNewSubfolderBeingCreated() throws {
        let vault = try makeVault()
        defer { vault.remove() }

        let result = try Filer(vaultRoot: vault.url)
            .file(request(newSubfolder: "Taxes", ledger: receiptLedger(amount: "1.00", folder: "Personal/Finances/Taxes")))

        #expect(result.ledgerURL == result.folderURL.appending(path: "2026 Business Receipts.md"))
    }

    @Test func rejectsAMissingLedgerFolderBeforeWritingTheDocument() throws {
        let vault = try makeVault()
        defer { vault.remove() }

        #expect(throws: FilingError.folderMissing("Personal/Finances/Taxes")) {
            try Filer(vaultRoot: vault.url).file(request(ledger: receiptLedger(amount: "1.00", folder: "Personal/Finances/Taxes")))
        }
        #expect(try regularFiles(in: vault.url).isEmpty)
    }

    @Test func rejectsALedgerFolderOutsideTheVaultBeforeWritingTheDocument() throws {
        let vault = try makeVault()
        defer { vault.remove() }

        #expect(throws: PathGuardError.escapesRoot("../elsewhere")) {
            try Filer(vaultRoot: vault.url).file(request(ledger: receiptLedger(amount: "1.00", folder: "../elsewhere")))
        }
        #expect(try regularFiles(in: vault.url).isEmpty)
    }

    @Test func rejectsALedgerNameThatSanitizesToEmpty() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        var ledger = receiptLedger(amount: "1.00")
        ledger.noteName = "???"

        #expect(throws: FilingError.invalidLedgerName("???")) {
            try Filer(vaultRoot: vault.url).file(request(ledger: ledger))
        }
        #expect(try regularFiles(in: vault.url).isEmpty)
    }
}
