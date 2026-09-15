import Foundation

/// Runs a staged batch through OCR, Claude, the filing rules, and the Filer, recording every step (spec §6–§13).
/// Use one processor per vault: `DocumentFiler` runs synchronously on this actor, so documents never interleave
/// writes to the same folder or ledger (Milestone 2 ADR).
public actor BatchProcessor {
    let configuration: PipelineConfiguration
    let services: PipelineServices

    public init(configuration: PipelineConfiguration, services: PipelineServices) {
        self.configuration = configuration
        self.services = services
    }

    public func process(_ batch: StagedBatch) async throws -> BatchSnapshot {
        var log = try await services.events.events(forBatch: batch.id)
        if log.isEmpty {
            try await adopt(batch)
            log = try await services.events.events(forBatch: batch.id)
        }
        if case .failed = BatchProjection.snapshot(batchID: batch.id, events: log).status {
            return try await snapshot(of: batch.id)
        }
        let artifacts = BatchArtifacts(batchFolder: batch.folderURL, fileSystem: services.fileSystem)
        var step = BatchStep.ocr
        var documentID: String?
        do {
            let pageTexts = try await recognizedPages(of: batch, artifacts: artifacts, log: log)
            step = .readStack
            let stack = try await readStack(of: batch, pageTexts: pageTexts, artifacts: artifacts, log: log)
            step = .placeDocuments
            let current = try await snapshot(of: batch.id)
            for (index, document) in stack.documents.enumerated() where current.documents[BatchArtifacts.documentID(at: index)] == .pending {
                documentID = BatchArtifacts.documentID(at: index)
                try await handle(document, index: index, of: batch, stack: stack, pageTexts: pageTexts, artifacts: artifacts)
                documentID = nil
            }
            step = .archive
            if try await snapshot(of: batch.id).nextStep == .archive {
                _ = try StagingScanner(stagingRoot: configuration.stagingRoot, fileSystem: services.fileSystem).archive(batch)
                try await record(.rawArchived, batch: batch.id)
            }
        } catch {
            try await record(.stepFailed, batch: batch.id, document: documentID,
                             payload: [JobPayloadKey.step: step.rawValue, JobPayloadKey.message: String(describing: error)])
        }
        return try await snapshot(of: batch.id)
    }

    func adopt(_ batch: StagedBatch) async throws {
        var payload = [JobPayloadKey.source: batch.manifest.source.rawValue]
        payload[JobPayloadKey.purpose] = batch.manifest.purpose
        try await record(.batchAdopted, batch: batch.id, payload: payload)
        if let purpose = batch.manifest.purpose {
            try await services.purposes.recordUse(purpose)
        }
    }

    func recognizedPages(of batch: StagedBatch, artifacts: BatchArtifacts, log: [JobEvent]) async throws -> [PageText] {
        let pageTexts: [PageText]
        if let saved = try artifacts.loadOCR() {
            pageTexts = saved
        } else {
            let files = try StagingScanner(stagingRoot: configuration.stagingRoot, fileSystem: services.fileSystem).pageFiles(of: batch)
            let refs = try services.pages.pageRefs(for: files)
            guard !refs.isEmpty else { throw PipelineError.noPages }
            pageTexts = try await BatchOCR.recognize(pages: refs, in: batch.folderURL, source: services.pages, recognizer: services.recognizer)
            try artifacts.saveOCR(pageTexts)
        }
        if !log.contains(where: { $0.kind == .ocrCompleted }) {
            try await record(.ocrCompleted, batch: batch.id, payload: [JobPayloadKey.pages: String(pageTexts.count)])
        }
        return pageTexts
    }

    func readStack(of batch: StagedBatch, pageTexts: [PageText], artifacts: BatchArtifacts, log: [JobEvent]) async throws -> StoredStack {
        var payload: [String: String] = [:]
        let stack: StoredStack
        if let saved = try artifacts.loadStack() {
            stack = saved
        } else {
            let inputs = try pageTexts.enumerated().map { index, page in
                StackPageInput(number: index + 1,
                               jpeg: try services.pages.claudeJPEG(page.page, in: batch.folderURL, maxLongEdge: configuration.model.maxImageLongEdge),
                               ocrText: page.text)
            }
            let result = try await StackReader(claude: services.claude, model: configuration.model).read(pages: inputs, purpose: batch.manifest.purpose)
            stack = StoredStack(result.outcome, pageCount: pageTexts.count)
            try artifacts.saveStack(stack)
            payload = PipelinePayload.usage(result.usage, model: configuration.model)
        }
        if !log.contains(where: { $0.kind == .stackRead }) {
            payload[JobPayloadKey.documentIDs] = stack.documents.indices.map(BatchArtifacts.documentID(at:)).joined(separator: ",")
            try await record(.stackRead, batch: batch.id, payload: payload)
        }
        return stack
    }

    func snapshot(of batchID: String) async throws -> BatchSnapshot {
        BatchProjection.snapshot(batchID: batchID, events: try await services.events.events(forBatch: batchID))
    }

    func record(_ kind: JobEventKind, batch batchID: String, document documentID: String? = nil, payload: [String: String] = [:]) async throws {
        try await services.events.append(JobEvent(batchID: batchID, documentID: documentID, at: services.now(), kind: kind, payload: payload))
    }
}
