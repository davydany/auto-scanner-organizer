import Foundation

/// Everything the filing step needs about one document.
struct FilingContext {
    var batch: StagedBatch
    var document: DocumentAnalysis
    var documentIndex: Int
    var stack: StoredStack
    var placement: StoredPlacement
    var pageTexts: [PageText]
    var mapping: PurposeMapping?
}

enum FilingStepOutcome: Equatable {
    case review(reasons: [ReviewReason], folder: String?)
    case filed(StoredFiling, createdFolder: Bool)
    case ledgerRejected(StoredFiling, createdFolder: Bool, reason: String)
    case ledgerFailed(StoredFiling, createdFolder: Bool, message: String)
}

/// Decides and files one document with no suspension point between the duplicate and ledger checks and the writes,
/// so a `BatchProcessor` actor runs filing one document at a time (Milestone 1 carry-forwards, Milestone 2 ADR).
struct DocumentFiler {
    let configuration: PipelineConfiguration
    let fileSystem: any FileSystem
    let pages: any PageImageSource

    static func join(_ folder: String, _ subfolder: String?) -> String {
        [folder, subfolder ?? ""].filter { !$0.isEmpty }.joined(separator: "/")
    }

    func fileOrReview(_ context: FilingContext) throws -> FilingStepOutcome {
        guard case let .placed(placement, fromPurposeMapping) = context.placement else {
            return .review(reasons: context.placement.reviewReasons, folder: nil)
        }
        let filer = Filer(vaultRoot: configuration.vaultRoot, fileSystem: fileSystem)
        let folderURL: URL
        do {
            guard fileSystem.isDirectory(at: try filer.vault.resolve(placement.folder)) else {
                return .review(reasons: [.folderMissing(folder: placement.folder)], folder: placement.folder)
            }
            folderURL = try filer.destinationURL(folder: placement.folder, newSubfolder: placement.newSubfolder)
        } catch {
            return .review(reasons: [.validationFailed(message: "The chosen folder can't be used: \(error)")], folder: placement.folder)
        }
        let document = context.document
        let docDate = document.docDate ?? CalendarDay.from(context.batch.manifest.startedAt, timeZone: configuration.timeZone)
        let destination = Self.join(placement.folder, placement.newSubfolder)
        let ledgerTarget = LedgerTarget(context: context, placement: placement, destination: destination)
        let decision = FilingDecider.decide(DecisionInput(
            threshold: configuration.threshold, splitConfidence: document.splitConfidence,
            splitOnChunkBoundary: context.stack.boundaryDocumentIndices.contains(context.documentIndex),
            placementConfidence: placement.confidence, placementFromPurposeMapping: fromPurposeMapping,
            createsTopLevelFolder: placement.folder.isEmpty && placement.newSubfolder != nil,
            hasPurpose: context.batch.manifest.purpose != nil, purposeFit: document.purposeFit,
            goesToLedger: ledgerTarget.goesToLedger, amountPresent: document.keyFacts.ledgerAmount != nil,
            duplicateOf: try filer.findDuplicate(in: folderURL, docDate: docDate, from: document.from, title: document.title),
            ledgerValid: ledgerTarget.isValid(with: filer)
        ))
        if case .needsReview(let reasons) = decision {
            return .review(reasons: reasons, folder: placement.folder)
        }
        let ledger = ledgerTarget.filing(for: document)
        let request = FilingRequest(destinationFolder: placement.folder, newSubfolder: placement.newSubfolder, pdfData: try pdfData(for: context),
                                    note: note(for: context, placement: placement, fromPurposeMapping: fromPurposeMapping, docDate: docDate, filer: filer),
                                    ledger: ledger)
        func stored(_ result: FilingResult, ledgerUpdated: Bool) -> StoredFiling {
            StoredFiling(baseName: result.baseName, folder: destination, docDate: docDate, ledger: ledger, ledgerUpdated: ledgerUpdated)
        }
        do {
            let result = try filer.file(request)
            return .filed(stored(result, ledgerUpdated: true), createdFolder: result.createdFolder)
        } catch FilingError.ledgerUpdateFailed(.ledger(let error), let result) {
            return .ledgerRejected(stored(result, ledgerUpdated: false), createdFolder: result.createdFolder, reason: String(describing: error))
        } catch FilingError.ledgerUpdateFailed(.io(let message), let result) {
            return .ledgerFailed(stored(result, ledgerUpdated: false), createdFolder: result.createdFolder, message: message)
        } catch FilingError.folderMissing(let folder) {
            return .review(reasons: [.folderMissing(folder: folder)], folder: placement.folder)
        }
    }

    private func pdfData(for context: FilingContext) throws -> Data {
        let inputs = try context.document.pages.map { number throws -> PDFPageInput in
            guard context.pageTexts.indices.contains(number - 1) else { throw PageImageError.unreadable("page \(number)") }
            let page = context.pageTexts[number - 1]
            let image = try pages.loadImage(page.page, in: context.batch.folderURL)
            return PDFPageInput(image: image.image, lines: page.lines, dpi: image.dpi)
        }
        return try SearchablePDFBuilder.build(pages: inputs)
    }

    private func note(for context: FilingContext, placement: Placement, fromPurposeMapping: Bool, docDate: CalendarDay, filer: Filer) -> NoteContent {
        let document = context.document
        let related = placement.relatedNotes.filter { name in
            (try? filer.vault.resolve("\(name).md")).map { fileSystem.fileExists(at: $0) } ?? false
        }
        return NoteContent(
            baseName: "", analysis: document, docDate: docDate, docDateEstimated: document.docDate == nil,
            scannedAt: context.batch.manifest.startedAt, timeZone: configuration.timeZone,
            filingConfidence: fromPurposeMapping ? document.splitConfidence : min(document.splitConfidence, placement.confidence),
            relatedNotes: related, scanPurpose: context.batch.manifest.purpose,
            pageTexts: document.pages.compactMap { context.pageTexts.indices.contains($0 - 1) ? context.pageTexts[$0 - 1].text : nil }
        )
    }
}

/// Where a purpose batch's ledger row goes (spec §10.4, §11).
struct LedgerTarget {
    var goesToLedger: Bool
    /// The purpose's folder: the remembered one, else this document's destination.
    var folder: String
    var noteName: String
    var purpose: String
    var fit: PurposeFit?

    init(context: FilingContext, placement: Placement, destination: String) {
        let purpose = context.batch.manifest.purpose
        fit = context.document.purposeFit
        goesToLedger = purpose != nil && fit?.fits == true
        folder = context.mapping?.folder ?? destination
        noteName = context.mapping?.ledgerNoteName ?? placement.ledgerNoteName ?? FilenameBuilder.sanitize(purpose ?? "")
        self.purpose = purpose ?? ""
    }

    func isValid(with filer: Filer) -> Bool {
        guard goesToLedger else { return true }
        guard let url = try? filer.vault.resolve(folder) else { return false }
        return filer.ledgerIsValid(in: url, noteName: noteName)
    }

    /// Nil unless the document goes to the ledger with an amount and a valid currency (never defaulted).
    func filing(for document: DocumentAnalysis) -> LedgerFiling? {
        guard goesToLedger, let amount = document.keyFacts.ledgerAmount else { return nil }
        return LedgerFiling(noteName: noteName, folder: folder, title: noteName, purpose: purpose, taxYear: fit?.taxYear, from: document.from ?? "",
                            amount: amount.amount, currency: amount.currency, category: fit?.expenseCategory ?? .other)
    }
}
