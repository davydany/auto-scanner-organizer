import Foundation

public enum StackFailure: Codable, Sendable, Equatable {
    case refused(category: String)
    case invalid(messages: [String])

    public var reviewReason: ReviewReason {
        switch self {
        case .refused(let category): .refused(category: category)
        case .invalid(let messages): .validationFailed(message: messages.joined(separator: " "))
        }
    }
}

/// The read-stack result, stored in `.scancore/stack.json`.
public struct StoredStack: Codable, Sendable, Equatable {
    public var documents: [DocumentAnalysis]
    /// Sorted indices of documents next to a chunk boundary (spec §8.1).
    public var boundaryDocumentIndices: [Int]
    /// Set when Claude refused or stayed invalid; `documents` then holds one document covering every page, for review (spec §13).
    public var failure: StackFailure?

    public init(documents: [DocumentAnalysis], boundaryDocumentIndices: [Int], failure: StackFailure?) {
        self.documents = documents
        self.boundaryDocumentIndices = boundaryDocumentIndices
        self.failure = failure
    }

    public init(_ outcome: StackReadOutcome, pageCount: Int) {
        switch outcome {
        case let .read(documents, boundary):
            self.init(documents: documents, boundaryDocumentIndices: boundary.sorted(), failure: nil)
        case .refused(let category):
            self.init(documents: [Self.wholeBatch(pageCount)], boundaryDocumentIndices: [], failure: .refused(category: category))
        case .invalid(let messages):
            self.init(documents: [Self.wholeBatch(pageCount)], boundaryDocumentIndices: [], failure: .invalid(messages: messages))
        }
    }

    static func wholeBatch(_ pageCount: Int) -> DocumentAnalysis {
        DocumentAnalysis(pages: Array(1...max(pageCount, 1)), splitConfidence: 0, docType: .other, title: "Unreadable Scan",
                         summary: "Claude could not read this batch, so it needs review.")
    }
}

/// A document's placement, stored in `.scancore/placement-<documentID>.json`.
public enum StoredPlacement: Codable, Sendable, Equatable {
    case placed(placement: Placement, fromPurposeMapping: Bool)
    case refused(category: String)
    case invalid(messages: [String])

    public init(_ outcome: PlacementOutcome) {
        switch outcome {
        case .placed(let placement): self = .placed(placement: placement, fromPurposeMapping: false)
        case .refused(let category): self = .refused(category: category)
        case .invalid(let messages): self = .invalid(messages: messages)
        }
    }

    public init(stackFailure: StackFailure) {
        switch stackFailure {
        case .refused(let category): self = .refused(category: category)
        case .invalid(let messages): self = .invalid(messages: messages)
        }
    }

    public var reviewReasons: [ReviewReason] {
        switch self {
        case .placed: []
        case .refused(let category): [.refused(category: category)]
        case .invalid(let messages): [.validationFailed(message: messages.joined(separator: " "))]
        }
    }
}

/// A document whose PDF and note are written, stored in `.scancore/filing-<documentID>.json`, so a failed ledger
/// step is retried with `Filer.updateLedger` and never by filing again (Milestone 1 carry-forward).
public struct StoredFiling: Codable, Sendable, Equatable {
    public var baseName: String
    /// Vault-relative folder that holds the PDF and note.
    public var folder: String
    public var docDate: CalendarDay
    public var ledger: LedgerFiling?
    public var ledgerUpdated: Bool

    public init(baseName: String, folder: String, docDate: CalendarDay, ledger: LedgerFiling?, ledgerUpdated: Bool) {
        self.baseName = baseName
        self.folder = folder
        self.docDate = docDate
        self.ledger = ledger
        self.ledgerUpdated = ledgerUpdated
    }
}

/// Step outputs kept in the batch's hidden `.scancore/` folder so a resumed batch never repeats OCR or Claude requests
/// (Milestone 2 ADR). They move to `_done/` with the batch.
public struct BatchArtifacts: Sendable {
    public static let folderName = ".scancore"

    public static func documentID(at index: Int) -> String {
        "doc-\(index + 1)"
    }

    public static func documentIndex(of documentID: String) -> Int? {
        guard documentID.hasPrefix("doc-"), let number = Int(documentID.dropFirst(4)), number >= 1,
              documentID == Self.documentID(at: number - 1)
        else { return nil }
        return number - 1
    }

    public let folder: URL
    private let fileSystem: any FileSystem

    public init(batchFolder: URL, fileSystem: any FileSystem = LocalFileSystem()) {
        folder = batchFolder.appending(path: Self.folderName)
        self.fileSystem = fileSystem
    }

    public func saveOCR(_ pages: [PageText]) throws {
        try save(pages, as: "ocr.json")
    }

    public func loadOCR() throws -> [PageText]? {
        try load([PageText].self, from: "ocr.json")
    }

    public func saveStack(_ stack: StoredStack) throws {
        try save(stack, as: "stack.json")
    }

    public func loadStack() throws -> StoredStack? {
        try load(StoredStack.self, from: "stack.json")
    }

    public func savePlacement(_ placement: StoredPlacement, documentID: String) throws {
        try save(placement, as: "placement-\(documentID).json")
    }

    public func loadPlacement(documentID: String) throws -> StoredPlacement? {
        try load(StoredPlacement.self, from: "placement-\(documentID).json")
    }

    public func saveFiling(_ filing: StoredFiling, documentID: String) throws {
        try save(filing, as: "filing-\(documentID).json")
    }

    public func loadFiling(documentID: String) throws -> StoredFiling? {
        try load(StoredFiling.self, from: "filing-\(documentID).json")
    }

    private func save(_ value: some Encodable, as name: String) throws {
        try fileSystem.createDirectory(at: folder)
        try fileSystem.writeAtomically(try ScanCoreJSON.encoder().encode(value), to: folder.appending(path: name))
    }

    private func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let url = folder.appending(path: name)
        guard fileSystem.fileExists(at: url) else { return nil }
        return try ScanCoreJSON.decoder().decode(T.self, from: try fileSystem.readData(at: url))
    }
}
