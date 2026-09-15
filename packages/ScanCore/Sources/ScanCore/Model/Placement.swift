import Foundation

public struct PlacementAlternative: Codable, Sendable, Equatable {
    public var folder: String
    public var confidence: Double

    public init(folder: String, confidence: Double) {
        self.folder = folder
        self.confidence = confidence
    }
}

/// Claude's "file document" answer (spec §8.3).
public struct Placement: Codable, Sendable, Equatable {
    public var folder: String
    public var newSubfolder: String?
    public var relatedNotes: [String]
    public var confidence: Double
    public var reason: String
    public var alternatives: [PlacementAlternative]
    /// For purpose batches: Claude's proposed Title Case ledger note name, already validated (Milestone 2 ADR).
    public var ledgerNoteName: String?

    public init(folder: String, newSubfolder: String? = nil, relatedNotes: [String] = [], confidence: Double,
                reason: String, alternatives: [PlacementAlternative] = [], ledgerNoteName: String? = nil) {
        self.folder = folder
        self.newSubfolder = newSubfolder
        self.relatedNotes = relatedNotes
        self.confidence = confidence
        self.reason = reason
        self.alternatives = alternatives
        self.ledgerNoteName = ledgerNoteName
    }
}
