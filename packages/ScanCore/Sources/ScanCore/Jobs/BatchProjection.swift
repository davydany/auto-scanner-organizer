import Foundation

public enum BatchStep: String, Codable, Sendable {
    case scan, ocr, readStack, placeDocuments, archive, done
}

public enum DocumentStatus: Sendable, Equatable {
    case pending, needsReview, filed, failed
}

public enum BatchStatus: Sendable, Equatable {
    case scanning
    case interrupted
    case processing
    case needsReview
    case filed
    case failed(step: BatchStep, message: String)
}

public struct BatchSnapshot: Sendable, Equatable {
    public var batchID: String
    public var status: BatchStatus
    public var nextStep: BatchStep
    public var documentIDs: [String]
    public var documents: [String: DocumentStatus]
}

/// Derives batch and document status from the event log (spec §12). Nothing is stored separately.
public enum BatchProjection {
    public static func snapshot(batchID: String, events: [JobEvent]) -> BatchSnapshot {
        var nextStep: BatchStep = .scan
        var documentIDs: [String] = []
        var documents: [String: DocumentStatus] = [:]
        var interrupted = false
        var failure: (step: BatchStep, message: String)?

        for event in events where event.batchID == batchID {
            switch event.kind {
            case .scanStarted:
                interrupted = false
                nextStep = .scan
            case .scanInterrupted:
                interrupted = true
            case .scanCompleted, .batchAdopted:
                interrupted = false
                nextStep = .ocr
            case .ocrCompleted:
                nextStep = .readStack
            case .stackRead:
                let allIDs = (event.payload[JobPayloadKey.documentIDs] ?? "").split(separator: ",").map(String.init)
                var seen: Set<String> = []
                documentIDs = allIDs.filter { seen.insert($0).inserted }
                documents = Dictionary(uniqueKeysWithValues: documentIDs.map { ($0, DocumentStatus.pending) })
                nextStep = .placeDocuments
            case .needsReview:
                if let id = event.documentID { documents[id] = .needsReview }
            case .reviewResolved:
                if let id = event.documentID { documents[id] = .pending }
            case .noteWritten:
                if let id = event.documentID, event.payload[JobPayloadKey.ledger] != "pending" { documents[id] = .filed }
            case .ledgerUpdated:
                if let id = event.documentID { documents[id] = .filed }
            case .rawArchived:
                nextStep = .done
            case .stepFailed:
                let step = BatchStep(rawValue: event.payload[JobPayloadKey.step] ?? "") ?? nextStep
                failure = (step, event.payload[JobPayloadKey.message] ?? "Unknown error")
                if let id = event.documentID { documents[id] = .failed }
            case .retryRequested:
                failure = nil
                for (id, status) in documents where status == .failed {
                    documents[id] = .pending
                }
            case .pageScanned, .placementDecided, .folderCreated, .pdfWritten:
                break
            }
        }

        let allFiled = !documentIDs.isEmpty && documentIDs.allSatisfy { documents[$0] == .filed }
        if nextStep == .placeDocuments, allFiled {
            nextStep = .archive
        }

        let status = determineStatus(failure: failure, interrupted: interrupted, nextStep: nextStep, documents: documents, allFiled: allFiled)
        return BatchSnapshot(batchID: batchID, status: status, nextStep: nextStep, documentIDs: documentIDs, documents: documents)
    }

    private static func determineStatus(
        failure: (step: BatchStep, message: String)?,
        interrupted: Bool,
        nextStep: BatchStep,
        documents: [String: DocumentStatus],
        allFiled: Bool
    ) -> BatchStatus {
        if let failure {
            return .failed(step: failure.step, message: failure.message)
        }
        if interrupted {
            return .interrupted
        }
        if nextStep == .scan {
            return .scanning
        }
        if documents.values.contains(.needsReview) {
            return .needsReview
        }
        if allFiled {
            return .filed
        }
        return .processing
    }
}
