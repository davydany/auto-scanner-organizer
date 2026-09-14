import Foundation

public struct LedgerFiling: Sendable, Equatable {
    public var noteName: String
    public var title: String
    public var purpose: String
    public var taxYear: Int?
    public var from: String
    public var amount: Decimal
    public var currency: String
    public var category: ExpenseCategory

    public init(noteName: String, title: String, purpose: String, taxYear: Int?, from: String, amount: Decimal,
                currency: String, category: ExpenseCategory) {
        self.noteName = noteName
        self.title = title
        self.purpose = purpose
        self.taxYear = taxYear
        self.from = from
        self.amount = amount
        self.currency = currency
        self.category = category
    }
}

public struct FilingRequest: Sendable, Equatable {
    public var destinationFolder: String
    public var newSubfolder: String?
    public var pdfData: Data
    /// `note.baseName` is ignored; the Filer computes the final base name.
    public var note: NoteContent
    public var ledger: LedgerFiling?

    public init(destinationFolder: String, newSubfolder: String?, pdfData: Data, note: NoteContent, ledger: LedgerFiling?) {
        self.destinationFolder = destinationFolder
        self.newSubfolder = newSubfolder
        self.pdfData = pdfData
        self.note = note
        self.ledger = ledger
    }
}

public struct FilingResult: Sendable, Equatable {
    public var baseName: String
    public var folderURL: URL
    public var pdfURL: URL
    public var noteURL: URL
    public var createdFolder: Bool
    public var ledgerURL: URL?
}

public enum FilingError: Error, Equatable, Sendable {
    case invalidSubfolder(String)
    case folderMissing(String)
    case ledgerUpdateFailed(LedgerError, result: FilingResult)
}

/// Writes a document into the vault in spec §10.5 order: folder → PDF → note → ledger.
public struct Filer: Sendable {
    public let vault: VaultPathGuard
    private let fileSystem: any FileSystem

    public init(vaultRoot: URL, fileSystem: any FileSystem = LocalFileSystem()) {
        vault = VaultPathGuard(root: vaultRoot)
        self.fileSystem = fileSystem
    }

    public func destinationURL(folder: String, newSubfolder: String?) throws -> URL {
        guard let subfolder = newSubfolder else { return try vault.resolve(folder) }
        guard !subfolder.isEmpty, !subfolder.contains("/"), !subfolder.hasPrefix(".") else {
            throw FilingError.invalidSubfolder(subfolder)
        }
        return try vault.resolve(folder.isEmpty ? subfolder : "\(folder)/\(subfolder)")
    }

    public func file(_ request: FilingRequest) throws -> FilingResult {
        let parent = try vault.resolve(request.destinationFolder)
        let folderURL = try destinationURL(folder: request.destinationFolder, newSubfolder: request.newSubfolder)
        guard fileSystem.isDirectory(at: parent) else { throw FilingError.folderMissing(request.destinationFolder) }
        let createdFolder = !fileSystem.isDirectory(at: folderURL)
        if createdFolder {
            try fileSystem.createDirectory(at: folderURL)
        }

        let existingNames = Set(try fileSystem.contentsOfDirectory(at: folderURL).map(\.lastPathComponent))
        let analysis = request.note.analysis
        let baseName = FilenameBuilder.uniqueBaseName(
            FilenameBuilder.baseName(date: request.note.docDate, from: analysis.from, title: analysis.title),
            existingFileNames: existingNames
        )
        var note = request.note
        note.baseName = baseName
        if let ledger = request.ledger {
            // NoteWriter only emits the `ledger:` front-matter line when `scanPurpose` is set,
            // so filing under a ledger's purpose surfaces that purpose on the note as well.
            note.scanPurpose = ledger.purpose
            note.ledgerNoteName = FilenameBuilder.sanitize(ledger.noteName)
        }

        let pdfURL = folderURL.appending(path: "\(baseName).pdf")
        let noteURL = folderURL.appending(path: "\(baseName).md")
        // Create-only writes: a filed document never replaces an existing file, even one the listing missed.
        try fileSystem.createNewFile(request.pdfData, at: pdfURL)
        do {
            try fileSystem.createNewFile(Data(NoteWriter.render(note).utf8), at: noteURL)
        } catch {
            // Spec §13: a vault write failure must not leave a partial file behind.
            // The PDF was created by this call, so removing it can never delete an owner file.
            try? fileSystem.removeItem(at: pdfURL)
            throw error
        }

        var result = FilingResult(baseName: baseName, folderURL: folderURL, pdfURL: pdfURL, noteURL: noteURL,
                                  createdFolder: createdFolder, ledgerURL: nil)
        if let ledger = request.ledger {
            do {
                result.ledgerURL = try updateLedger(ledger, documentNoteName: baseName, docDate: note.docDate, in: folderURL)
            } catch let error as LedgerError {
                throw FilingError.ledgerUpdateFailed(error, result: result)
            }
        }
        return result
    }

    public func updateLedger(_ ledger: LedgerFiling, documentNoteName: String, docDate: CalendarDay, in folderURL: URL) throws -> URL {
        let url = folderURL.appending(path: "\(FilenameBuilder.sanitize(ledger.noteName)).md")
        var document: LedgerDocument
        if fileSystem.fileExists(at: url) {
            // Spec §14: never read a note that a symlink smuggles in from outside the vault.
            guard vault.contains(url) else { throw LedgerError.markersMissing }
            guard let text = String(data: try fileSystem.readData(at: url), encoding: .utf8) else {
                throw LedgerError.markersMissing
            }
            document = try LedgerDocument.parse(text)
        } else {
            document = LedgerDocument.new(title: ledger.title, purpose: ledger.purpose, taxYear: ledger.taxYear)
        }
        try document.upsert(LedgerRow(date: docDate, from: ledger.from, amount: ledger.amount, currency: ledger.currency,
                                      category: ledger.category, documentNoteName: documentNoteName))
        try fileSystem.writeAtomically(Data(document.render().utf8), to: url)
        return url
    }

    public func ledgerIsValid(in folderURL: URL, noteName: String) -> Bool {
        let url = folderURL.appending(path: "\(FilenameBuilder.sanitize(noteName)).md")
        guard fileSystem.fileExists(at: url) else { return true }
        // Spec §14: a note symlinked in from outside the vault is never usable.
        guard vault.contains(url) else { return false }
        guard let data = try? fileSystem.readData(at: url), let text = String(data: data, encoding: .utf8) else { return false }
        return (try? LedgerDocument.parse(text)) != nil
    }

    public func findDuplicate(in folderURL: URL, docDate: CalendarDay, from: String?, title: String) throws -> String? {
        guard fileSystem.isDirectory(at: folderURL) else { return nil }
        // Front matter may have folded whitespace differently depending on how it was written
        // (e.g. `\r\n` vs `\n`, runs of blank lines); compare both sides after the same normalization
        // so duplicate detection isn't sensitive to whitespace styling.
        let normalizedTitle = Self.normalizedForComparison(title)
        let normalizedFrom = from.map(Self.normalizedForComparison)
        for url in try fileSystem.contentsOfDirectory(at: folderURL) where url.pathExtension == "md" {
            // Spec §14: directory listings don't resolve symlinks, so skip anything that escapes the vault.
            guard vault.contains(url) else { continue }
            guard let text = String(data: try fileSystem.readData(at: url), encoding: .utf8) else { continue }
            let properties = FrontMatterReader.properties(of: text)
            guard properties["type"] != "ledger" else { continue }
            let noteTitle = properties["title"].map(Self.normalizedForComparison)
            let noteFrom = properties["from"].map(Self.normalizedForComparison)
            if properties["doc_date"] == docDate.description, noteTitle == normalizedTitle, noteFrom == normalizedFrom {
                return url.deletingPathExtension().lastPathComponent
            }
        }
        return nil
    }

    /// Collapses every run of whitespace (spaces, tabs, `\r`, `\n`, `\r\n`) into a single space, trims both ends,
    /// and lowercases, so duplicate matching isn't sensitive to line breaks or letter case.
    private static func normalizedForComparison(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
