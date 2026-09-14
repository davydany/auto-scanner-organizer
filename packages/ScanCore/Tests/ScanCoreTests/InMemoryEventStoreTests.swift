import Foundation
import Testing
@testable import ScanCore

struct InMemoryEventStoreTests {
    @Test func returnsBatchEventsInAppendOrderAndNewestBatchFirst() async throws {
        let store = InMemoryEventStore()
        let first = JobEvent(batchID: "a", at: Date(timeIntervalSince1970: 1), kind: .scanStarted)
        let second = JobEvent(batchID: "b", at: Date(timeIntervalSince1970: 2), kind: .scanStarted)
        let third = JobEvent(batchID: "a", at: Date(timeIntervalSince1970: 3), kind: .scanCompleted)
        for event in [first, second, third] {
            try await store.append(event)
        }
        #expect(try await store.events(forBatch: "a") == [first, third])
        #expect(try await store.batchIDs() == ["b", "a"])
    }

    @Test func eventsRoundTripThroughJSON() throws {
        let event = JobEvent(batchID: "a", documentID: "d1", at: Date(timeIntervalSince1970: 5), kind: .needsReview,
                             payload: ["reason": "uncertainPlacement"])
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(JobEvent.self, from: data) == event)
    }

    @Test func eventsRoundTripThroughScanCoreJSON() throws {
        let event = JobEvent(batchID: "2026-09-13-224203", documentID: "d1", at: Date(timeIntervalSince1970: 5), kind: .noteWritten, payload: [JobPayloadKey.ledger: "pending"])
        let data = try ScanCoreJSON.encoder().encode(event)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"batch_id\":\"2026-09-13-224203\""))
        #expect(json.contains("\"document_id\":\"d1\""))
        #expect(try ScanCoreJSON.decoder().decode(JobEvent.self, from: data) == event)
    }
}
