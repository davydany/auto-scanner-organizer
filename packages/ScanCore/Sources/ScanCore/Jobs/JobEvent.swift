import Foundation

public enum JobEventKind: String, Codable, Sendable, CaseIterable {
    case scanStarted, pageScanned, scanCompleted, scanInterrupted, batchAdopted, ocrCompleted, stackRead
    case placementDecided, needsReview, reviewResolved, folderCreated, pdfWritten, noteWritten, ledgerUpdated
    case rawArchived, stepFailed, retryRequested
}

public enum JobPayloadKey {
    /// On `stackRead`: comma-separated document IDs in page order.
    public static let documentIDs = "documentIDs"
    /// On `noteWritten`: `"pending"` when a ledger update must follow before the document counts as filed.
    public static let ledger = "ledger"
    /// On `stepFailed`: the `BatchStep` raw value that failed.
    public static let step = "step"
    /// On `stepFailed`: human-readable reason shown in History.
    public static let message = "message"
}

/// One append-only entry in a batch's history (spec §12).
public struct JobEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var batchID: String
    public var documentID: String?
    public var at: Date
    public var kind: JobEventKind
    public var payload: [String: String]

    public init(id: UUID = UUID(), batchID: String, documentID: String? = nil, at: Date, kind: JobEventKind,
                payload: [String: String] = [:]) {
        self.id = id
        self.batchID = batchID
        self.documentID = documentID
        self.at = at
        self.kind = kind
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case batchID = "batchId"
        case documentID = "documentId"
        case at
        case kind
        case payload
    }
}
