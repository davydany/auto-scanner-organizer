import Foundation

extension BatchProcessor {
    func handle(_ document: DocumentAnalysis, index: Int, of batch: StagedBatch, stack: StoredStack, pageTexts: [PageText],
                artifacts: BatchArtifacts) async throws {
        let documentID = BatchArtifacts.documentID(at: index)
        if let filing = try artifacts.loadFiling(documentID: documentID) {
            try await resumeFiling(filing, documentID: documentID, batch: batch, artifacts: artifacts)
            return
        }
        var mapping: PurposeMapping?
        if let purpose = batch.manifest.purpose {
            mapping = try await services.purposes.mapping(for: purpose)
        }
        let resolution = try artifacts.loadResolution(documentID: documentID)
        let placement: StoredPlacement
        if let resolution {
            placement = try resolvedPlacement(resolution, documentID: documentID, artifacts: artifacts)
        } else if let failure = stack.failure {
            placement = StoredPlacement(stackFailure: failure)
        } else {
            placement = try await decidePlacement(for: document, documentID: documentID, batch: batch, mapping: mapping, artifacts: artifacts)
        }
        var context = FilingContext(batch: batch, document: resolution?.applied(to: document) ?? document, documentIndex: index, stack: stack,
                                    placement: placement, pageTexts: pageTexts, mapping: mapping)
        context.approval = resolution.map { ReviewApproval(acceptPossibleDuplicate: $0.acceptPossibleDuplicate) }
        let outcome = try DocumentFiler(configuration: configuration, fileSystem: services.fileSystem, pages: services.pages).fileOrReview(context)
        try await recordOutcome(outcome, documentID: documentID, batch: batch, artifacts: artifacts)
    }

    func decidePlacement(for document: DocumentAnalysis, documentID: String, batch: StagedBatch, mapping: PurposeMapping?,
                         artifacts: BatchArtifacts) async throws -> StoredPlacement {
        let recorded = try await services.events.events(forBatch: batch.id).contains { $0.kind == .placementDecided && $0.documentID == documentID }
        if let saved = try artifacts.loadPlacement(documentID: documentID) {
            if !recorded { try await recordPlacement(saved, payload: [:], documentID: documentID, batch: batch.id) }
            return saved
        }
        let placement: StoredPlacement
        var payload: [String: String] = [:]
        if let mapping {
            placement = .placed(placement: Placement(folder: mapping.folder, confidence: 1, reason: "Same folder as earlier filings for this purpose.",
                                                     ledgerNoteName: mapping.ledgerNoteName), fromPurposeMapping: true)
        } else {
            let index = VaultIndex.render(try VaultIndex.build(root: configuration.vaultRoot, fileSystem: services.fileSystem))
            let agent = PlacementAgent(claude: services.claude, model: configuration.model, vaultRoot: configuration.vaultRoot, vaultIndex: index,
                                       fileSystem: services.fileSystem)
            let result = try await agent.place(document, purpose: batch.manifest.purpose)
            placement = StoredPlacement(result.outcome)
            payload = PipelinePayload.usage(result.usage, model: configuration.model)
        }
        try artifacts.savePlacement(placement, documentID: documentID)
        try await recordPlacement(placement, payload: payload, documentID: documentID, batch: batch.id)
        return placement
    }

    func recordPlacement(_ placement: StoredPlacement, payload: [String: String], documentID: String, batch batchID: String) async throws {
        var payload = payload
        if case let .placed(value, _) = placement {
            payload[JobPayloadKey.folder] = DocumentFiler.join(value.folder, value.newSubfolder)
            payload[JobPayloadKey.confidence] = String(value.confidence)
        }
        try await record(.placementDecided, batch: batchID, document: documentID, payload: payload)
    }

    func recordOutcome(_ outcome: FilingStepOutcome, documentID: String, batch: StagedBatch, artifacts: BatchArtifacts) async throws {
        switch outcome {
        case let .review(reasons, folder):
            var payload = [JobPayloadKey.reasons: PipelinePayload.encodeReasons(reasons)]
            payload[JobPayloadKey.folder] = folder
            try await record(.needsReview, batch: batch.id, document: documentID, payload: payload)
        case .filed(let filing):
            try artifacts.saveFiling(filing, documentID: documentID)
            try await recordWrites(filing, documentID: documentID, batch: batch.id)
            try await finishFiling(filing, documentID: documentID, batch: batch)
        case let .ledgerRejected(filing, reason):
            try artifacts.saveFiling(filing, documentID: documentID)
            try await recordWrites(filing, documentID: documentID, batch: batch.id)
            try await record(.needsReview, batch: batch.id, document: documentID,
                             payload: [JobPayloadKey.reasons: PipelinePayload.encodeReasons([.ledgerRejected(reason: reason)])])
        case let .ledgerFailed(filing, message):
            try artifacts.saveFiling(filing, documentID: documentID)
            try await recordWrites(filing, documentID: documentID, batch: batch.id)
            throw PipelineError.ledgerWriteFailed(message)
        }
    }

    /// Records each vault write the document's events don't already hold, so a filing resumed after a lost event records it once.
    func recordWrites(_ filing: StoredFiling, documentID: String, batch batchID: String) async throws {
        let recorded = try await recordedKinds(of: documentID, batch: batchID)
        if filing.createdFolder, !recorded.contains(.folderCreated) {
            try await record(.folderCreated, batch: batchID, document: documentID, payload: [JobPayloadKey.folder: filing.folder])
        }
        if !recorded.contains(.pdfWritten) {
            try await record(.pdfWritten, batch: batchID, document: documentID, payload: [JobPayloadKey.noteName: filing.baseName])
        }
        if !recorded.contains(.noteWritten) {
            var payload = [JobPayloadKey.noteName: filing.baseName, JobPayloadKey.folder: filing.folder]
            if filing.ledger != nil {
                payload[JobPayloadKey.ledger] = "pending"
            }
            try await record(.noteWritten, batch: batchID, document: documentID, payload: payload)
        }
    }

    /// Remembers the purpose's folder, then records the ledger update once; the first filing that updates the purpose's ledger wins (spec §11).
    /// A filing without a ledger, such as a document resolved in review that doesn't fit the purpose, never sets it.
    /// `ledgerUpdated` marks the document filed, so it comes last: if remembering fails, the retry still finishes the document.
    func finishFiling(_ filing: StoredFiling, documentID: String, batch: StagedBatch) async throws {
        guard let ledger = filing.ledger else { return }
        if let purpose = batch.manifest.purpose {
            _ = try await services.purposes.saveIfAbsent(PurposeMapping(purpose: purpose, folder: ledger.folder, ledgerNoteName: ledger.noteName,
                                                                        createdAt: services.now()))
        }
        if try await !recordedKinds(of: documentID, batch: batch.id).contains(.ledgerUpdated) {
            try await record(.ledgerUpdated, batch: batch.id, document: documentID, payload: [JobPayloadKey.noteName: ledger.noteName])
        }
    }

    func recordedKinds(of documentID: String, batch batchID: String) async throws -> [JobEventKind] {
        try await services.events.events(forBatch: batchID).filter { $0.documentID == documentID }.map(\.kind)
    }
}
