import Foundation
import Testing
@testable import ScanCore

/// Forwards to a real `LocalFileSystem`, except that every directory lists as empty —
/// simulates a listing that missed a file created a moment earlier, so the Filer's
/// computed base name collides with a file that already exists.
private struct StaleListingFileSystem: FileSystem {
    private let inner = LocalFileSystem()

    func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { inner.isDirectory(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { [] }
    func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try inner.readData(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws { try inner.writeAtomically(data, to: url) }
    func createNewFile(_ data: Data, at url: URL) throws { try inner.createNewFile(data, at: url) }
    func moveItem(at source: URL, to destination: URL) throws { try inner.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try inner.removeItem(at: url) }
}

extension FilerTests {
    @Test func titleDifferingOnlyInCaseIsADuplicateAndNeverOverwritesTheEarlierFiling() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let filer = Filer(vaultRoot: vault.url)
        var firstRequest = request(title: "Electric bill")
        firstRequest.pdfData = Data("%PDF-first".utf8)
        let first = try filer.file(firstRequest)

        #expect(try filer.findDuplicate(in: first.folderURL, docDate: CalendarDay("2026-08-28")!,
                                         from: "Dominion Energy", title: "Electric Bill") == first.baseName)
        let second = try filer.file(request(title: "Electric Bill"))
        #expect(second.baseName == "2026-08-28 Dominion Energy - Electric Bill (2)")
        #expect(try Data(contentsOf: first.pdfURL) == Data("%PDF-first".utf8))
    }

    @Test func neverReplacesAnExistingPDFOrNoteWhenTheListingMissesThem() throws {
        let vault = try makeVault()
        defer { vault.remove() }
        let folder = vault.url.appending(path: "Personal/Finances")
        let filer = Filer(vaultRoot: vault.url, fileSystem: StaleListingFileSystem())

        let ownerPDF = folder.appending(path: "2026-08-28 Dominion Energy - Electric Bill.pdf")
        try Data("owner pdf".utf8).write(to: ownerPDF)
        #expect(throws: (any Error).self) { try filer.file(request()) }
        #expect(try Data(contentsOf: ownerPDF) == Data("owner pdf".utf8))

        try FileManager.default.removeItem(at: ownerPDF)
        let ownerNote = folder.appending(path: "2026-08-28 Dominion Energy - Electric Bill.md")
        try Data("owner note".utf8).write(to: ownerNote)
        #expect(throws: (any Error).self) { try filer.file(request()) }
        #expect(try Data(contentsOf: ownerNote) == Data("owner note".utf8))
        // The PDF written just before the refused note is cleaned up; no temp files remain.
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.sorted() == ["2026-08-28 Dominion Energy - Electric Bill.md"])
    }
}
