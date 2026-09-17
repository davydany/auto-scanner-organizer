import Foundation

public struct LedgerFiling: Codable, Sendable, Equatable {
    public var noteName: String
    /// Vault-relative folder of the purpose; the ledger note lives here (spec §10.4).
    public var folder: String
    public var title: String
    public var purpose: String
    public var taxYear: Int?
    public var from: String
    public var amount: Decimal
    public var currency: String
    public var category: ExpenseCategory

    public init(noteName: String, folder: String, title: String, purpose: String, taxYear: Int?, from: String, amount: Decimal,
                currency: String, category: ExpenseCategory) {
        self.noteName = noteName
        self.folder = folder
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

/// Why the ledger step failed after the PDF and note were written.
public enum LedgerFailure: Error, Equatable, Sendable {
    case ledger(LedgerError)
    /// Any other error from the ledger step (e.g. a failed read or write), as `String(describing:)`.
    case io(String)
}

public enum FilingError: Error, Equatable, Sendable {
    case invalidSubfolder(String)
    case folderMissing(String)
    case hiddenFolder(String)
    case invalidLedgerName(String)
    /// The PDF and note were written; retry with `Filer.updateLedger` using `result`, never by re-running `file(_:)`.
    case ledgerUpdateFailed(LedgerFailure, result: FilingResult)
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
        // Everything that can reject the request is checked before the first write.
        try Self.rejectHiddenComponents(of: request.destinationFolder)
        if let ledger = request.ledger {
            try Self.rejectHiddenComponents(of: ledger.folder)
        }
        let parent = try vault.resolve(request.destinationFolder)
        let folderURL = try destinationURL(folder: request.destinationFolder, newSubfolder: request.newSubfolder)
        let ledgerTarget = try request.ledger.map { try resolvedLedgerTarget(Self.masked($0)) }
        guard fileSystem.isDirectory(at: parent) else { throw FilingError.folderMissing(request.destinationFolder) }
        let createdFolder = !fileSystem.isDirectory(at: folderURL)
        if createdFolder {
            try fileSystem.createDirectory(at: folderURL)
        }
        // Checked after creating the subfolder: the purpose's folder may be the subfolder just created.
        if let ledgerTarget, !fileSystem.isDirectory(at: ledgerTarget.folderURL) {
            throw FilingError.folderMissing(ledgerTarget.filing.folder)
        }

        let existingNames = Set(try fileSystem.contentsOfDirectory(at: folderURL).map(\.lastPathComponent))
        // Spec §10.2: Claude's fields are masked once, here, before they reach the filename or the note.
        let analysis = Self.masked(request.note.analysis)
        let baseName = FilenameBuilder.uniqueBaseName(
            FilenameBuilder.baseName(
                date: request.note.docDate,
                from: analysis.from.map { SensitiveNumberMasker.mask(FilenameBuilder.sanitize($0)) },
                title: SensitiveNumberMasker.mask(FilenameBuilder.sanitize(analysis.title))
            ),
            existingFileNames: existingNames
        )
        var note = request.note
        note.analysis = analysis
        note.baseName = baseName
        if let ledgerTarget {
            // NoteWriter only emits the `ledger:` front-matter line when `scanPurpose` is set,
            // so filing under a ledger's purpose surfaces that purpose on the note as well.
            note.scanPurpose = ledgerTarget.filing.purpose
            note.ledgerNoteName = ledgerTarget.noteName
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
        if let ledgerTarget {
            result.ledgerURL = try updateLedgerStep(ledgerTarget, keeping: result, docDate: note.docDate)
        }
        return result
    }

    /// A ledger filing whose folder and note name passed validation.
    private struct LedgerTarget {
        let filing: LedgerFiling
        let folderURL: URL
        let noteName: String
    }

    private func resolvedLedgerTarget(_ ledger: LedgerFiling) throws -> LedgerTarget {
        let folderURL = try vault.resolve(ledger.folder)
        let noteName = Self.ledgerNoteBaseName(ledger.noteName)
        guard !noteName.isEmpty, !noteName.hasPrefix(".") else { throw FilingError.invalidLedgerName(ledger.noteName) }
        return LedgerTarget(filing: ledger, folderURL: folderURL, noteName: noteName)
    }

    /// Wraps every ledger-step error so the caller keeps the result of the document already written.
    private func updateLedgerStep(_ target: LedgerTarget, keeping result: FilingResult, docDate: CalendarDay) throws -> URL {
        do {
            return try updateLedger(target.filing, documentNoteName: result.baseName, docDate: docDate, in: target.folderURL)
        } catch let error as LedgerError {
            throw FilingError.ledgerUpdateFailed(.ledger(error), result: result)
        } catch {
            throw FilingError.ledgerUpdateFailed(.io(String(describing: error)), result: result)
        }
    }

    /// Dot-folders (`.obsidian`, `.trash`) are hidden from the owner, so nothing is filed into them.
    /// `.` and `..` are path navigation and stay VaultPathGuard's concern.
    private static func rejectHiddenComponents(of folder: String) throws {
        let isHidden = folder.split(separator: "/").contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
        if isHidden { throw FilingError.hiddenFolder(folder) }
    }

    public func updateLedger(_ ledger: LedgerFiling, documentNoteName: String, docDate: CalendarDay, in folderURL: URL) throws -> URL {
        // Masked here too, so a retry with the caller's unmasked filing reaches the same ledger note.
        let ledger = Self.masked(ledger)
        let url = folderURL.appending(path: "\(Self.ledgerNoteBaseName(ledger.noteName)).md")
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
        let url = folderURL.appending(path: "\(Self.ledgerNoteBaseName(noteName)).md")
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
        let normalizedFrom = Self.normalizedSender(from)
        for url in try fileSystem.contentsOfDirectory(at: folderURL) where url.pathExtension == "md" {
            // Spec §14: directory listings don't resolve symlinks, so skip anything that escapes the vault.
            guard vault.contains(url) else { continue }
            guard let text = String(data: try fileSystem.readData(at: url), encoding: .utf8) else { continue }
            let properties = FrontMatterReader.properties(of: text)
            guard properties["type"] != "ledger" else { continue }
            let noteTitle = properties["title"].map(Self.normalizedForComparison)
            let noteFrom = Self.normalizedSender(properties["from"])
            if properties["doc_date"] == docDate.description, noteTitle == normalizedTitle, noteFrom == normalizedFrom {
                return url.deletingPathExtension().lastPathComponent
            }
        }
        return nil
    }

    /// Masks sensitive numbers (as the Filer does before writing), collapses every run of whitespace
    /// (spaces, tabs, `\r`, `\n`, `\r\n`) into a single space, trims both ends, and lowercases, so duplicate
    /// matching isn't sensitive to masking, line breaks, or letter case.
    private static func normalizedForComparison(_ text: String) -> String {
        SensitiveNumberMasker.mask(collapsedWhitespace(text)).split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Collapses every run of whitespace (including line breaks) into one space and trims both ends,
    /// so a number split across lines is contiguous before masking.
    private static func collapsedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A sender that is empty after normalization counts as no sender, as in NoteWriter and FilenameBuilder.
    private static func normalizedSender(_ text: String?) -> String? {
        guard let normalized = text.map(normalizedForComparison), !normalized.isEmpty else { return nil }
        return normalized
    }

    /// The ledger note's file base name: masked, then stripped of filename-forbidden characters.
    private static func ledgerNoteBaseName(_ noteName: String) -> String {
        FilenameBuilder.sanitize(SensitiveNumberMasker.mask(noteName))
    }

    /// Masks the fields of Claude's analysis that the Filer writes outside NoteWriter's own masking
    /// (summary, handwriting raw text, and page text are masked by NoteWriter).
    private static func masked(_ analysis: DocumentAnalysis) -> DocumentAnalysis {
        var analysis = analysis
        analysis.title = SensitiveNumberMasker.mask(collapsedWhitespace(analysis.title))
        analysis.from = analysis.from.map { SensitiveNumberMasker.mask(collapsedWhitespace($0)) }
        analysis.handwritten = analysis.handwritten.map { annotation in
            var annotation = annotation
            annotation.paymentMethod = annotation.paymentMethod.map { SensitiveNumberMasker.mask(collapsedWhitespace($0)) }
            annotation.checkNumber = annotation.checkNumber.map { SensitiveNumberMasker.mask(collapsedWhitespace($0)) }
            return annotation
        }
        analysis.keyFacts.accountLast4 = analysis.keyFacts.accountLast4.flatMap(lastFourDigits)
        return analysis
    }

    /// At most the last four ASCII digits; nil when there are none, so the optional property is left out.
    private static func lastFourDigits(_ value: String) -> String? {
        let digits = String(value.filter { $0.isASCII && $0.isNumber }.suffix(4))
        return digits.isEmpty ? nil : digits
    }

    private static func masked(_ ledger: LedgerFiling) -> LedgerFiling {
        var ledger = ledger
        ledger.noteName = SensitiveNumberMasker.mask(collapsedWhitespace(ledger.noteName))
        ledger.title = SensitiveNumberMasker.mask(collapsedWhitespace(ledger.title))
        ledger.from = SensitiveNumberMasker.mask(collapsedWhitespace(ledger.from))
        return ledger
    }
}
