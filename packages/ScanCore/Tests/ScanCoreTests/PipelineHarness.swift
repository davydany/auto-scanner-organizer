import Foundation
@testable import ScanCore

/// A temporary staging folder and vault (Personal/Finances, Work) with in-memory stores, for BatchProcessor tests.
struct PipelineHarness {
    static let startedAt = Date(timeIntervalSince1970: 1_789_349_400) // 2026-09-14T01:30:00Z
    static let utc = TimeZone(identifier: "UTC") ?? .current

    let temp: TemporaryDirectory
    let staging: URL
    let vault: URL
    let events = InMemoryEventStore()
    let purposes = InMemoryPurposeStore()

    init() throws {
        temp = try TemporaryDirectory()
        staging = temp.url.appending(path: "Staging")
        vault = temp.url.appending(path: "Vault")
        for folder in [staging, vault.appending(path: "Personal/Finances"), vault.appending(path: "Work")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func remove() {
        temp.remove()
    }

    func stageBatch(id: String = "2026-09-14-013000", pages: Int, purpose: String? = nil) throws -> StagedBatch {
        let folder = staging.appending(path: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for number in 1...pages {
            try Data().write(to: folder.appending(path: String(format: "page-%03d.png", number)))
        }
        let manifest = BatchManifest(id: id, source: .scanner, scanner: "Canon", settings: nil, purpose: purpose, pages: pages,
                                     startedAt: Self.startedAt, completedAt: Self.startedAt, interrupted: nil)
        try ScanCoreJSON.encoder().encode(manifest).write(to: folder.appending(path: BatchManifest.fileName))
        return StagedBatch(id: id, folderURL: folder, manifest: manifest)
    }

    func processor(claude: any ClaudeMessaging, recognizer: any TextRecognizer = FakeTextRecognizer(),
                   fileSystem: any FileSystem & FileAttributesReading = LocalFileSystem(), events: (any EventStore)? = nil,
                   purposes: (any PurposeStore)? = nil, threshold: Double = 0.75) -> BatchProcessor {
        BatchProcessor(
            configuration: PipelineConfiguration(stagingRoot: staging, vaultRoot: vault, model: .sonnet5, threshold: threshold, timeZone: Self.utc),
            services: PipelineServices(fileSystem: fileSystem, events: events ?? self.events, purposes: purposes ?? self.purposes, pages: FakePageSource(),
                                       recognizer: recognizer, claude: claude, now: { PipelineHarness.startedAt })
        )
    }

    func vaultFiles(_ folder: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: vault.appending(path: folder).path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    func text(_ vaultPath: String) throws -> String {
        try String(contentsOf: vault.appending(path: vaultPath), encoding: .utf8)
    }

    func kinds(_ batchID: String, document: String? = nil) async throws -> [JobEventKind] {
        try await events.events(forBatch: batchID).filter { document == nil || $0.documentID == document }.map(\.kind)
    }

    static func submit(_ id: String, _ input: JSONValue) -> ScriptedClaude.Step {
        ScriptedClaude.toolUse([ScriptedClaude.ToolCall(id: id, name: "submit_placement", input: input)])
    }
}
