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
        let placement: StoredPlacement
        if let failure = stack.failure {
            placement = StoredPlacement(stackFailure: failure)
        } else {
            placement = try await decidePlacement(for: document, documentID: documentID, batch: batch, mapping: mapping, artifacts: artifacts)
        }
        let context = FilingContext(batch: batch, document: document, documentIndex: index, stack: stack, placement: placement,
                                    pageTexts: pageTexts, mapping: mapping)
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
        case let .filed(filing, createdFolder):
            try artifacts.saveFiling(filing, documentID: documentID)
            try await recordWrites(filing, createdFolder: createdFolder, documentID: documentID, batch: batch.id)
            try await finishFiling(filing, documentID: documentID, batch: batch)
        case let .ledgerRejected(filing, createdFolder, reason):
            try artifacts.saveFiling(filing, documentID: documentID)
            try await recordWrites(filing, createdFolder: createdFolder, documentID: documentID, batch: batch.id)
            try await record(.needsReview, batch: batch.id, document: documentID,
                             payload: [JobPayloadKey.reasons: PipelinePayload.encodeReasons([.ledgerRejected(reason: reason)])])
        case let .ledgerFailed(filing, createdFolder, message):
            try artifacts.saveFiling(filing, documentID: documentID)
            try await recordWrites(filing, createdFolder: createdFolder, documentID: documentID, batch: batch.id)
            throw PipelineError.ledgerWriteFailed(message)
        }
    }

    func recordWrites(_ filing: StoredFiling, createdFolder: Bool, documentID: String, batch batchID: String) async throws {
        if createdFolder {
            try await record(.folderCreated, batch: batchID, document: documentID, payload: [JobPayloadKey.folder: filing.folder])
        }
        try await record(.pdfWritten, batch: batchID, document: documentID, payload: [JobPayloadKey.noteName: filing.baseName])
        var payload = [JobPayloadKey.noteName: filing.baseName, JobPayloadKey.folder: filing.folder]
        if filing.ledger != nil {
            payload[JobPayloadKey.ledger] = "pending"
        }
        try await record(.noteWritten, batch: batchID, document: documentID, payload: payload)
    }

    /// Records the ledger update and remembers the purpose's folder; the first successful filing wins (spec §11).
    func finishFiling(_ filing: StoredFiling, documentID: String, batch: StagedBatch) async throws {
        if let ledger = filing.ledger {
            try await record(.ledgerUpdated, batch: batch.id, document: documentID, payload: [JobPayloadKey.noteName: ledger.noteName])
        }
        if let purpose = batch.manifest.purpose {
            _ = try await services.purposes.saveIfAbsent(PurposeMapping(purpose: purpose, folder: filing.ledger?.folder ?? filing.folder,
                                                                        ledgerNoteName: filing.ledger?.noteName, createdAt: services.now()))
        }
    }
}
