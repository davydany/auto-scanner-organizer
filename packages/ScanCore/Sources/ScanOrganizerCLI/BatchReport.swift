import Foundation
import ScanCore

/// Plain-text batch history for the terminal: one line per batch, then one line per document that isn't filed.
enum BatchReport {
    static func lines(for snapshot: BatchSnapshot, events: [JobEvent]) -> [String] {
        let reviewCount = snapshot.documentIDs.filter { snapshot.documents[$0] == .needsReview }.count
        let total = snapshot.documentIDs.count
        var lines = ["\(snapshot.batchID)  \(status(snapshot.status, reviewCount: reviewCount, total: total))"]
        for documentID in snapshot.documentIDs {
            switch snapshot.documents[documentID] {
            case .needsReview:
                let payload = events.last { $0.kind == .needsReview && $0.documentID == documentID }?.payload[JobPayloadKey.reasons]
                lines.append("  \(documentID)  needs review: " + PipelinePayload.decodeReasons(payload).map(describe).joined(separator: "; "))
            case .failed:
                lines.append("  \(documentID)  failed")
            case .pending:
                lines.append("  \(documentID)  pending")
            case .filed, nil:
                continue
            }
        }
        return lines
    }

    static func describe(_ reason: ReviewReason) -> String {
        switch reason {
        case .uncertainSplit(let confidence): "uncertain split (\(String(format: "%.2f", confidence)))"
        case .splitOnChunkBoundary: "split falls on a 20-page chunk boundary"
        case .uncertainPlacement(let confidence): "uncertain folder (\(String(format: "%.2f", confidence)))"
        case .newTopLevelFolder: "would create a new top-level folder"
        case .purposeMismatch(let reason): "doesn't fit the purpose: \(reason)"
        case .missingAmount: "no amount with a currency for the ledger"
        case .possibleDuplicate(let name): "possible duplicate of [[\(name)]]"
        case .ledgerNeedsAttention: "the ledger note needs attention"
        case .refused(let category): "Claude declined (\(category))"
        case .validationFailed(let message): "Claude's answer was invalid: \(message)"
        case .folderMissing(let folder): "folder \"\(folder)\" no longer exists"
        case .ledgerRejected(let reason): "the ledger rejected the row: \(reason)"
        }
    }

    private static func status(_ status: BatchStatus, reviewCount: Int, total: Int) -> String {
        switch status {
        case .scanning: "scanning"
        case .interrupted: "interrupted"
        case .processing: "processing"
        case .needsReview: "needs review (\(reviewCount) of \(total) documents)"
        case .filed: "filed (\(total) document\(total == 1 ? "" : "s"))"
        case let .failed(step, message): "failed at \(step.rawValue): \(message)"
        }
    }
}
