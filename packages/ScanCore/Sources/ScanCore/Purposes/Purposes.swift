import Foundation

public enum PurposeKey {
    /// Lowercased, trimmed, whitespace collapsed (spec §11).
    public static func normalize(_ purpose: String) -> String {
        purpose.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Spec §11: most recent first, distinct by key, at most `limit`; blank purposes are ignored.
    public static func updatedRecents(_ recents: [String], using purpose: String, limit: Int) -> [String] {
        let trimmed = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recents }
        let key = normalize(trimmed)
        var updated = recents.filter { normalize($0) != key }
        updated.insert(trimmed, at: 0)
        return Array(updated.prefix(limit))
    }
}

public struct PurposeMapping: Codable, Sendable, Equatable {
    public var purpose: String
    public var folder: String
    public var ledgerNoteName: String?
    public var createdAt: Date

    public var key: String { PurposeKey.normalize(purpose) }

    public init(purpose: String, folder: String, ledgerNoteName: String?, createdAt: Date) {
        self.purpose = purpose
        self.folder = folder
        self.ledgerNoteName = ledgerNoteName
        self.createdAt = createdAt
    }
}

public protocol PurposeStore: Sendable {
    func mapping(for purpose: String) async throws -> PurposeMapping?
    /// Stores the mapping only when none exists for its key; returns whichever mapping is stored.
    func saveIfAbsent(_ mapping: PurposeMapping) async throws -> PurposeMapping
    func recordUse(_ purpose: String) async throws
    /// Most recent first, distinct by key.
    func recentPurposes() async throws -> [String]
}

public actor InMemoryPurposeStore: PurposeStore {
    public static let recentLimit = 8

    private var mappings: [String: PurposeMapping] = [:]
    private var recents: [String] = []

    public init() {}

    public func mapping(for purpose: String) async throws -> PurposeMapping? {
        mappings[PurposeKey.normalize(purpose)]
    }

    public func saveIfAbsent(_ mapping: PurposeMapping) async throws -> PurposeMapping {
        if let existing = mappings[mapping.key] { return existing }
        mappings[mapping.key] = mapping
        return mapping
    }

    public func recordUse(_ purpose: String) async throws {
        recents = PurposeKey.updatedRecents(recents, using: purpose, limit: Self.recentLimit)
    }

    public func recentPurposes() async throws -> [String] {
        recents
    }
}
