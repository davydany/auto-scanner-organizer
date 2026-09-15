import Foundation

extension BatchProcessor {
    /// Clears a failed step so the next `process` call resumes where it stopped (spec §13). Does nothing unless the batch failed.
    public func retry(batchID: String) async throws {
        guard case .failed = try await snapshot(of: batchID).status else { return }
        try await record(.retryRequested, batch: batchID)
    }

    /// Finishes a document whose PDF and note are already written: records any write events a crash lost, then
    /// updates only the ledger with `Filer.updateLedger` — never files again (spec §10.4, Milestone 1 carry-forward).
    func resumeFiling(_ stored: StoredFiling, documentID: String, batch: StagedBatch, artifacts: BatchArtifacts) async throws {
        var filing = stored
        let recorded = try await services.events.events(forBatch: batch.id).filter { $0.documentID == documentID }.map(\.kind)
        if !recorded.contains(.noteWritten) {
            try await recordWrites(filing, createdFolder: false, documentID: documentID, batch: batch.id)
        }
        if let ledger = filing.ledger, !filing.ledgerUpdated {
            let filer = Filer(vaultRoot: configuration.vaultRoot, fileSystem: services.fileSystem)
            do {
                _ = try filer.updateLedger(ledger, documentNoteName: filing.baseName, docDate: filing.docDate, in: try filer.vault.resolve(ledger.folder))
            } catch let error as LedgerError {
                try await record(.needsReview, batch: batch.id, document: documentID,
                                 payload: [JobPayloadKey.reasons: PipelinePayload.encodeReasons([.ledgerRejected(reason: String(describing: error))])])
                return
            }
            filing.ledgerUpdated = true
            try artifacts.saveFiling(filing, documentID: documentID)
        }
        try await finishFiling(filing, documentID: documentID, batch: batch)
    }
}
