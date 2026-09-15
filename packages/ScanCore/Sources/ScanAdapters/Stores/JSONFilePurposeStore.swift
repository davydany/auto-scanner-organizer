import Foundation
import ScanCore

/// Purpose mappings and recent purposes in one JSON file, rewritten atomically (Milestone 2 ADR).
public actor JSONFilePurposeStore: PurposeStore {
    struct Snapshot: Codable, Sendable {
        var mappings: [PurposeMapping] = []
        var recents: [String] = []
    }

    private let fileURL: URL
    private var snapshot: Snapshot?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func mapping(for purpose: String) async throws -> PurposeMapping? {
        let key = PurposeKey.normalize(purpose)
        return try load().mappings.first { $0.key == key }
    }

    public func saveIfAbsent(_ mapping: PurposeMapping) async throws -> PurposeMapping {
        var current = try load()
        if let existing = current.mappings.first(where: { $0.key == mapping.key }) { return existing }
        current.mappings.append(mapping)
        try persist(current)
        return mapping
    }

    public func recordUse(_ purpose: String) async throws {
        var current = try load()
        let updated = PurposeKey.updatedRecents(current.recents, using: purpose, limit: InMemoryPurposeStore.recentLimit)
        guard updated != current.recents else { return }
        current.recents = updated
        try persist(current)
    }

    public func recentPurposes() async throws -> [String] {
        try load().recents
    }

    private func load() throws -> Snapshot {
        if let snapshot { return snapshot }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            snapshot = Snapshot()
            return Snapshot()
        }
        let loaded = try ScanCoreJSON.decoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        snapshot = loaded
        return loaded
    }

    private func persist(_ updated: Snapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ScanCoreJSON.encoder().encode(updated).write(to: fileURL, options: .atomic)
        snapshot = updated
    }
}
