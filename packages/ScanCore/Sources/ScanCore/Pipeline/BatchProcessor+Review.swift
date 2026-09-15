import Foundation

extension BatchProcessor {
    /// Files a document from Needs review with the owner's folder and corrections, then continues the batch (spec §3, §11).
    /// The resolution is saved before it is recorded, so a crash right after resolving still files the document on the next run.
    public func resolveReview(_ batch: StagedBatch, documentID: String, resolution: ReviewResolution) async throws -> BatchSnapshot {
        guard try await snapshot(of: batch.id).documents[documentID] == .needsReview else {
            throw ReviewError.documentNotInReview(documentID)
        }
        let problems = problems(with: resolution)
        guard problems.isEmpty else { throw ReviewError.invalidResolution(problems) }
        try BatchArtifacts(batchFolder: batch.folderURL, fileSystem: services.fileSystem).saveResolution(resolution, documentID: documentID)
        try await record(.reviewResolved, batch: batch.id, document: documentID,
                         payload: [JobPayloadKey.folder: DocumentFiler.join(resolution.folder, resolution.newSubfolder)])
        return try await process(batch)
    }

    func problems(with resolution: ReviewResolution) -> [String] {
        let validator = PlacementValidator(vaultRoot: configuration.vaultRoot, fileSystem: services.fileSystem)
        var problems: [String] = []
        if let problem = validator.folderProblem(resolution.folder) { problems.append(problem) }
        if let name = resolution.newSubfolder, let problem = validator.subfolderProblem(name) { problems.append(problem) }
        if let title = resolution.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("title must not be blank.") }
        if let currency = resolution.currency, CurrencyCode.normalized(currency) == nil {
            problems.append("currency \"\(currency)\" must be a three-letter code such as USD.")
        }
        return problems
    }

    /// The owner's folder, keeping the related notes and ledger name from Claude's earlier placement.
    func resolvedPlacement(_ resolution: ReviewResolution, documentID: String, artifacts: BatchArtifacts) throws -> StoredPlacement {
        var earlier: Placement?
        if case let .placed(placement, _)? = try artifacts.loadPlacement(documentID: documentID) {
            earlier = placement
        }
        return .placed(placement: Placement(folder: resolution.folder, newSubfolder: resolution.newSubfolder, relatedNotes: earlier?.relatedNotes ?? [],
                                            confidence: 1, reason: "Chosen during review.", ledgerNoteName: earlier?.ledgerNoteName),
                       fromPurposeMapping: false)
    }
}
