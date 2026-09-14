import Foundation

public protocol EventStore: Sendable {
    func append(_ event: JobEvent) async throws
    /// Events for one batch in append order.
    func events(forBatch batchID: String) async throws -> [JobEvent]
    /// Batch IDs, most recently started first.
    func batchIDs() async throws -> [String]
}

public actor InMemoryEventStore: EventStore {
    private var storage: [JobEvent] = []

    public init() {}

    public func append(_ event: JobEvent) async throws {
        storage.append(event)
    }

    public func events(forBatch batchID: String) async throws -> [JobEvent] {
        storage.filter { $0.batchID == batchID }
    }

    public func batchIDs() async throws -> [String] {
        var firstSeen: [String: Date] = [:]
        for event in storage where firstSeen[event.batchID] == nil {
            firstSeen[event.batchID] = event.at
        }
        return firstSeen.sorted { $0.value > $1.value }.map(\.key)
    }
}
