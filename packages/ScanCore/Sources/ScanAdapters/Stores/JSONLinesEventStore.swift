import Foundation
import ScanCore

/// Append-only JSON Lines event log (Milestone 2 ADR). One `ScanCoreJSON` event per line.
public actor JSONLinesEventStore: EventStore {
    private let fileURL: URL
    private var cache: [JobEvent]?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ event: JobEvent) async throws {
        var events = try loadIfNeeded()
        var line = try ScanCoreJSON.encoder().encode(event)
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: fileURL)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
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

    private func loadIfNeeded() throws -> [JobEvent] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = ScanCoreJSON.decoder()
        var events: [JobEvent] = []
        let completeLength = data.last == 0x0A ? data.count : (data.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0)
        for line in data.prefix(completeLength).split(separator: 0x0A) {
            events.append(try decoder.decode(JobEvent.self, from: Data(line)))
        }
        if completeLength < data.count {
            // A crash mid-append left an unterminated final line; no completed event lives there.
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(completeLength))
        }
        cache = events
        return events
    }
}
