import Foundation
import ScanCore

/// Append-only JSON Lines event log (Milestone 2 ADR). One `ScanCoreJSON` event per line.
/// Readers never modify the file; only an append trims a fragment left by a crash or a failed append.
public actor JSONLinesEventStore: EventStore {
    private let fileURL: URL
    private var cache: [JobEvent]?
    /// Byte length of the complete lines behind `cache`; anything past it is an unterminated fragment.
    private var knownGoodLength: UInt64 = 0

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ event: JobEvent) async throws {
        // Decoding throws on an earlier corrupt line, before anything is written.
        var events = try loadIfNeeded()
        var line = try ScanCoreJSON.encoder().encode(event)
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: fileURL)
            knownGoodLength = 0
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        // Trimming relies on exactly one appending store per file. `DataDirectoryLock` excludes other processes, and callers in
        // one process must share this instance. Bytes past the known-good length are then a fragment from a crash or a
        // failed append, never another writer's event.
        if try handle.seekToEnd() > knownGoodLength {
            try handle.truncate(atOffset: knownGoodLength)
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        knownGoodLength += UInt64(line.count)
        events.append(event)
        cache = events
    }

    public func events(forBatch batchID: String) async throws -> [JobEvent] {
        try loadIfNeeded().filter { $0.batchID == batchID }
    }

    public func batchIDs() async throws -> [String] {
        var firstSeen: [String: Date] = [:]
        for event in try loadIfNeeded() where firstSeen[event.batchID] == nil {
            firstSeen[event.batchID] = event.at
        }
        return firstSeen.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Decodes every complete line and never modifies the file. An unterminated final line, from a crash mid-append or an
    /// append still in progress in the writing process, is ignored.
    private func loadIfNeeded() throws -> [JobEvent] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            cache = []
            knownGoodLength = 0
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let completeLength = data.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        let decoder = ScanCoreJSON.decoder()
        let events = try data.prefix(completeLength).split(separator: 0x0A).map { try decoder.decode(JobEvent.self, from: Data($0)) }
        knownGoodLength = UInt64(completeLength)
        cache = events
        return events
    }
}
